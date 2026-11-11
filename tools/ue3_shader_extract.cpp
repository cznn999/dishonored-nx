// Extracts every Xbox 360 shader container from Dishonored's cooked files, so the native renderer's shader package
// can be built from the whole game instead of from what one play session happened to draw.
//
//   ue3_shader_extract <output folder> <file or folder> [...]
//
// For each file (folders: every *.xxx, *.upk, *.bin under them):
//   - UE3 compressed chunks (tag 0x9E2A83C1, then block size, compressed / uncompressed sizes and one size pair per
//     block) are decompressed: every block is an XMemCompress LZX stream (frames prefixed by 0xFF + u16 frame size +
//     u16 block size, or by u16 block size for full 32 KB frames), window 128 KB;
//   - the plain bytes and every decompressed chunk are scanned for shader containers: magic 0x102A11xx, virtual size at
//     +4, physical (microcode) size at +8, the container is virtual + physical bytes;
//   - each container is written once (by content hash) as vs_<hash>.bin / ps_<hash>.bin; vertex or pixel is read from
//     the container's shader header (type byte of its first word).
//
// Only reads the game's files. Needs libmspack (the SDK's thirdparty/libmspack).

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <unordered_set>
#include <vector>

extern "C" {
#include <mspack.h>
#include <lzx.h>
}

namespace fs = std::filesystem;

static uint32_t BE32(const uint8_t* p) { return uint32_t(p[0]) << 24 | uint32_t(p[1]) << 16 | uint32_t(p[2]) << 8 | p[3]; }
static uint16_t BE16(const uint8_t* p) { return uint16_t(p[0] << 8 | p[1]); }

// --- a memory "file system" for libmspack ------------------------------------------------------------------------
struct MemFile {
  uint8_t* data;
  size_t size;
  size_t pos;
};
static mspack_file* MemOpen(mspack_system*, const char*, int) { return nullptr; }
static void MemClose(mspack_file*) {}
static int MemRead(mspack_file* f, void* buf, int n) {
  auto* m = reinterpret_cast<MemFile*>(f);
  size_t left = m->size - m->pos;
  size_t k = size_t(n) < left ? size_t(n) : left;
  memcpy(buf, m->data + m->pos, k);
  m->pos += k;
  return int(k);
}
static int MemWrite(mspack_file* f, void* buf, int n) {
  auto* m = reinterpret_cast<MemFile*>(f);
  size_t left = m->size - m->pos;
  size_t k = size_t(n) < left ? size_t(n) : left;
  memcpy(m->data + m->pos, buf, k);
  m->pos += k;
  return int(k);
}
static int MemSeek(mspack_file*, off_t, int) { return -1; }
static off_t MemTell(mspack_file* f) { return off_t(reinterpret_cast<MemFile*>(f)->pos); }
static void MemMessage(mspack_file*, const char*, ...) {}
static void* MemAlloc(mspack_system*, size_t n) { return malloc(n); }
static void MemFree(void* p) { free(p); }
static void MemCopy(void* s, void* d, size_t n) { memmove(d, s, n); }
static mspack_system g_sys = {MemOpen, MemClose, MemRead, MemWrite, MemSeek, MemTell, MemMessage,
                              MemAlloc, MemFree, MemCopy, nullptr};

// One XMemCompress block: strip the frame headers, then LZX-decode the joined frames (window 2^17).
static bool XMemDecompress(const uint8_t* src, size_t src_size, std::vector<uint8_t>& out, size_t out_size) {
  std::vector<uint8_t> raw;
  raw.reserve(src_size);
  size_t p = 0;
  while (p < src_size) {
    uint32_t block;
    if (src[p] == 0xFF) {
      if (p + 5 > src_size) break;
      block = BE16(src + p + 3);
      p += 5;
    } else {
      if (p + 2 > src_size) break;
      block = BE16(src + p);
      p += 2;
    }
    if (block == 0 || p + block > src_size) break;
    raw.insert(raw.end(), src + p, src + p + block);
    p += block;
  }
  out.assign(out_size, 0);
  MemFile in{raw.data(), raw.size(), 0};
  MemFile dst{out.data(), out.size(), 0};
  lzxd_stream* lzx = lzxd_init(&g_sys, reinterpret_cast<mspack_file*>(&in), reinterpret_cast<mspack_file*>(&dst),
                               17, 0, 1 << 16, off_t(out_size), 0);
  if (!lzx) return false;
  int r = lzxd_decompress(lzx, off_t(out_size));
  lzxd_free(lzx);
  return r == MSPACK_ERR_OK && dst.pos == out_size;
}

struct Stats {
  size_t files = 0, chunks = 0, chunk_failures = 0, containers = 0, written = 0, code_chunks = 0;
};

static std::unordered_set<uint64_t> g_seen;

static uint64_t Hash64(const uint8_t* p, size_t n) {  // FNV-1a 64
  uint64_t h = 1469598103934665603ull;
  for (size_t i = 0; i < n; ++i) h = (h ^ p[i]) * 1099511628211ull;
  return h;
}

static void ScanContainers(const uint8_t* d, size_t n, const fs::path& out, Stats& st) {
  for (size_t i = 0; i + 12 <= n; ++i) {
    if (d[i] != 0x10 || d[i + 1] != 0x2A || d[i + 2] != 0x11) continue;
    const uint32_t virt = BE32(d + i + 4), phys = BE32(d + i + 8);
    if (virt < 28 || virt > 0x40000 || !phys || phys > 0x40000 || i + virt + phys > n) continue;
    // The shader header the container points at (+24 = its offset in the virtual part) starts with the
    // microcode's offset and size; both must fit, or this is not a container.
    const uint32_t sh = BE32(d + i + 24);
    if (sh + 8 > virt) continue;
    const uint32_t code_off = BE32(d + i + sh), code_bytes = BE32(d + i + sh + 4);
    if (uint64_t(code_off) + code_bytes > phys || !code_bytes) continue;
    ++st.containers;
    const size_t size = size_t(virt) + phys;
    const uint64_t h = Hash64(d + i, size);
    if (!g_seen.insert(h).second) continue;
    // Vertex or pixel: byte 3 of the container magic (0x102A1100 = pixel, 0x102A1101 = vertex).
    const bool vertex = (d[i + 3] & 1) != 0;
    char name[64];
    snprintf(name, sizeof name, "%s_%016llx.bin", vertex ? "vs" : "ps", (unsigned long long)h);
    std::ofstream(out / name, std::ios::binary).write(reinterpret_cast<const char*>(d + i), std::streamsize(size));
    ++st.written;
    i += size - 1;
  }
}

// Whether src_size bytes are XMemCompress frames (then a zero block size and padding) that together hold out_size
// bytes: a cheap test before LZX.
static bool FramesFit(const uint8_t* src, size_t src_size, size_t out_size) {
  size_t p = 0, total = 0;
  while (p < src_size) {
    uint32_t block, frame;
    if (src[p] == 0xFF) {
      if (p + 5 > src_size) return false;
      frame = BE16(src + p + 1);
      block = BE16(src + p + 3);
      p += 5;
    } else {
      if (p + 2 > src_size) return false;
      frame = 0x8000;
      block = BE16(src + p);
      p += 2;
    }
    if (!block) break;  // the end: a zero block size, then a few bytes of padding
    if (!frame || frame > 0x8000 || p + block > src_size) return false;
    p += block;
    total += frame;
    if (total > out_size) return false;
  }
  return total == out_size && src_size - p <= 16;
}

// The material shaders: a package's shader cache (SeekFreeShaderCache, UE3's FCompressedShaderCodeChunk) keeps their
// code in chunks of their own, each one appCompressMemory call: u32 uncompressed size, u32 compressed size (TArray
// count), then one XMemCompress stream. Found by trying to decompress where those three fit; a chunk that decompresses
// to exactly its size is scanned for containers. Only the shader caches' global shaders are plain containers.
static void ScanCodeChunks(const uint8_t* d, size_t n, const fs::path& out, Stats& st) {
  for (size_t i = 0; i + 13 <= n; ++i) {
    const uint32_t U = BE32(d + i), C = BE32(d + i + 4);
    if (U < 64 || U > (16u << 20) || C < 8 || C > U + U / 8 + 256 || i + 8 + C > n) continue;
    const uint8_t* s = d + i + 8;
    if (s[0] == 0xFF) {
      const uint16_t fs = BE16(s + 1), bs = BE16(s + 3);
      // The first frame holds the first min(U, 32 KB) bytes; a frame header without 0xFF is a full 32 KB frame.
      if (fs != std::min<uint32_t>(U, 0x8000) || !bs || bs > C) continue;
    } else if (U < 0x8000 || !BE16(s) || BE16(s) > C) {
      continue;
    }
    if (!FramesFit(s, C, U)) continue;
    std::vector<uint8_t> code;
    if (!XMemDecompress(s, C, code, U)) continue;
    ++st.code_chunks;
    ScanContainers(code.data(), code.size(), out, st);
    i += 8 + size_t(C) - 1;
  }
}

static void ProcessFile(const fs::path& path, const fs::path& out, Stats& st) {
  std::ifstream f(path, std::ios::binary | std::ios::ate);
  std::vector<uint8_t> d(size_t(f.tellg()));
  f.seekg(0);
  f.read(reinterpret_cast<char*>(d.data()), std::streamsize(d.size()));
  ++st.files;
  printf("  [%zu] %s (%.1f MB), %zu shaders so far\n", st.files, path.filename().string().c_str(),
         d.size() / 1048576.0, st.written);
  fflush(stdout);
  ScanContainers(d.data(), d.size(), out, st);
  ScanCodeChunks(d.data(), d.size(), out, st);
  std::vector<uint8_t> unpacked;  // every compressed chunk's bytes, in order: code chunks may cross chunks
  // Compressed chunks.
  for (size_t c = 0; c + 16 <= d.size(); ++c) {
    if (BE32(d.data() + c) != 0x9E2A83C1u) continue;
    const uint32_t block_size = BE32(d.data() + c + 4);
    const uint32_t comp = BE32(d.data() + c + 8), uncomp = BE32(d.data() + c + 12);
    // UE3 writes 128 KB blocks; anything else is a chance match of the tag inside other data.
    if (block_size != 0x20000 || !uncomp || uncomp > (1u << 28) || comp > d.size() - c) continue;
    const uint32_t blocks = (uncomp + block_size - 1) / block_size;
    size_t table = c + 16, data = table + size_t(blocks) * 8;
    if (data > d.size()) continue;
    {
      uint64_t sum_c = 0, sum_u = 0;
      for (uint32_t b = 0; b < blocks; ++b) {
        sum_c += BE32(d.data() + table + b * 8);
        sum_u += BE32(d.data() + table + b * 8 + 4);
      }
      if (sum_c != comp || sum_u != uncomp || data + sum_c > d.size()) continue;
    }
    std::vector<uint8_t> whole;
    whole.reserve(uncomp);
    bool ok = true;
    for (uint32_t b = 0; b < blocks; ++b) {
      const uint32_t bc = BE32(d.data() + table + b * 8), bu = BE32(d.data() + table + b * 8 + 4);
      if (data + bc > d.size() || bu > block_size) { ok = false; break; }
      std::vector<uint8_t> part;
      if (!XMemDecompress(d.data() + data, bc, part, bu)) { ok = false; break; }
      whole.insert(whole.end(), part.begin(), part.end());
      data += bc;
    }
    ++st.chunks;
    if (!ok) { ++st.chunk_failures; continue; }
    ScanContainers(whole.data(), whole.size(), out, st);
    unpacked.insert(unpacked.end(), whole.begin(), whole.end());
    c = data - 1;
  }
  ScanCodeChunks(unpacked.data(), unpacked.size(), out, st);
}

int main(int argc, char** argv) {
  if (argc < 3) {
    fprintf(stderr, "usage: %s <output folder> <file or folder> [...]\n", argv[0]);
    return 1;
  }
  const fs::path out = argv[1];
  fs::create_directories(out);
  Stats st;
  for (int a = 2; a < argc; ++a) {
    const fs::path p = argv[a];
    if (fs::is_directory(p)) {
      for (const auto& e : fs::recursive_directory_iterator(p)) {
        if (!e.is_regular_file()) continue;
        auto ext = e.path().extension().string();
        for (auto& ch : ext) ch = char(tolower(ch));
        if (ext == ".xxx" || ext == ".upk" || ext == ".bin") {
          ProcessFile(e.path(), out, st);
        }
      }
    } else {
      ProcessFile(p, out, st);
    }
  }
  printf("%zu files, %zu compressed chunks (%zu failed), %zu shader code chunks, %zu containers found, %zu distinct written to %s\n",
         st.files, st.chunks, st.chunk_failures, st.code_chunks, st.containers, st.written, out.string().c_str());
  return 0;
}
