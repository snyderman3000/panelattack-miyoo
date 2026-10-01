-- FFI binding for libmini2d
local ffi = require("ffi")

ffi.cdef [[
typedef struct m2d_surf { uint32_t *px; uint64_t phy; int w, h, stride; uint32_t *rowidx; uint16_t *spans; } m2d_surf;
m2d_surf *m2d_surface_new(int w, int h);
void m2d_surface_free(m2d_surf *s);
size_t m2d_surface_bytes(m2d_surf *s);
m2d_surf *m2d_surface_view(m2d_surf *parent, int x, int y, int w, int h);
void m2d_surface_view_free(m2d_surf *s);
int m2d_surface_is_opaque(m2d_surf *s);
void m2d_surface_flatten(m2d_surf *s);
void m2d_surface_resample(m2d_surf *d, m2d_surf *src);
void m2d_surface_build_spans(m2d_surf *s);
void m2d_surface_upload_rgba(m2d_surf *s, const uint8_t *rgba, int sw, int sh);
void m2d_surface_upload_la8(m2d_surf *s, const uint8_t *la, int x0, int y0, int w, int h);
void m2d_surface_download_rgba(m2d_surf *s, uint8_t *rgba);
void m2d_surface_copy(m2d_surf *dst, m2d_surf *src);
m2d_surf *m2d_backbuffer(void);
void m2d_set_clip(int x, int y, int w, int h);
void m2d_reset_clip(void);
void m2d_clear(m2d_surf *d, uint32_t argb, int use_clip);
void m2d_fill(m2d_surf *d, int x, int y, int w, int h, uint32_t argb, int blend);
void m2d_blit(m2d_surf *s, int sx, int sy, int sw, int sh, m2d_surf *d, int dx, int dy, int dw, int dh, uint32_t tint, int blend, int flip);
void m2d_line(m2d_surf *d, int x0, int y0, int x1, int y1, int width, uint32_t argb, int blend);
void m2d_circle(m2d_surf *d, int cx, int cy, int r, uint32_t argb, int blend, int fill, int lw);
int m2d_init(int w, int h);
int m2d_fb_width(void);
int m2d_fb_height(void);
int m2d_frame_count(void);
void m2d_present(void);
int m2d_poll_key(int *code, int *value);
void m2d_quit(void);
void m2d_stats(double *out);
]]

local path = os.getenv("M2D_LIB") or "mini2d"
return ffi.load(path)
