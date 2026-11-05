/*
 * nouhs.efi - hide UHS-I (SDR50/SDR104/DDR50) from the SDC2 SD host before Windows starts.
 *
 * Windows sdbus would switch the card to 1.8 V signalling (CMD11) when the host advertises UHS-I,
 * but nothing in Windows moves the IO rail (PM6125 L5) to 1.8 V, and on Linux (pmOS) UHS never came
 * up on this slot either. Masking the UHS bits in Capabilities_1 keeps the card at 3.3 V high speed.
 *
 * sdhci-msm v5 (no MCI): SDHCI regs at 0x04784000, Capabilities_1 at 0x44. Qualcomm downstream
 * sdhci-msm writes SDHCI_CAPABILITIES_1 directly (regs_restore.hc_caps_1), so it is writable.
 *
 * Build: clang --target=aarch64-unknown-windows -ffreestanding -fshort-wchar -nostdlib
 *        -fuse-ld=lld -Wl,-entry:efi_main -Wl,-subsystem:efi_application -O2 -o nouhs.efi nouhs.c
 */
typedef unsigned long long u64;
typedef unsigned int u32;
typedef unsigned short u16;

#define SDC2_HC 0x04784000ULL
#define CAPS0 0x40
#define CAPS1 0x44
#define UHS_MASK 0x7u /* bit0 SDR50, bit1 SDR104, bit2 DDR50 */

struct out { void *reset; u64 (*print)(struct out *, u16 *); };
struct hdr { u64 sig; u32 rev, size, crc, res; };
struct bs { struct hdr h; void *fn[28]; u64 (*stall)(u64); };
struct st {
	struct hdr h; u16 *vendor; u32 frev; void *cin_h, *cin, *cout_h;
	struct out *cout; void *err_h, *err, *rt; struct bs *bs;
};

static struct out *con;

static void puts16(const char *s)
{
	u16 b[128]; int i = 0;
	while (*s && i < 126) { if (*s == '\n') b[i++] = '\r'; b[i++] = (u16)*s++; }
	b[i] = 0; con->print(con, b);
}

static void hex(u32 v)
{
	char b[11] = "0x"; int i;
	for (i = 0; i < 8; i++) b[2 + i] = "0123456789abcdef"[(v >> (28 - 4 * i)) & 0xf];
	b[10] = 0; puts16(b);
}

static inline u32 rd(u32 off) { return *(volatile u32 *)(SDC2_HC + off); }
static inline void wr(u32 off, u32 v) { *(volatile u32 *)(SDC2_HC + off) = v; }

u64 efi_main(void *image, struct st *st)
{
	u32 c0, c1, n;
	(void)image;
	con = st->cout;
	c0 = rd(CAPS0); c1 = rd(CAPS1);
	puts16("nouhs: SDC2 caps0 "); hex(c0); puts16(" caps1 "); hex(c1); puts16("\n");
	if (c1 & UHS_MASK) {
		wr(CAPS1, c1 & ~UHS_MASK);
		n = rd(CAPS1);
		puts16("nouhs: caps1 now "); hex(n);
		puts16((n & UHS_MASK) ? "  (NOT writable, UHS still on)\n" : "  (UHS off)\n");
	} else {
		puts16("nouhs: UHS already off\n");
	}
	st->bs->stall(3000000);
	return 0;
}
