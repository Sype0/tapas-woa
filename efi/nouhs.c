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
#define VCAPS0 0x21c /* CORE_VENDOR_SPEC_CAPABILITIES0 (v5) */
#define VCAPS1 0x220 /* CORE_VENDOR_SPEC_CAPABILITIES1 (v5) */
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
	u32 c0, c1, n, v0, v1;
	(void)image;
	con = st->cout;
	c0 = rd(CAPS0); c1 = rd(CAPS1);
	v0 = rd(VCAPS0); v1 = rd(VCAPS1);
	puts16("nouhs: SDC2 caps0 "); hex(c0); puts16(" caps1 "); hex(c1); puts16("\n");
	puts16("nouhs: vendor 0x21c "); hex(v0); puts16(" 0x220 "); hex(v1); puts16("\n");
	if (!(c1 & UHS_MASK)) {
		puts16("nouhs: UHS already off\n");
		goto out;
	}
	/* 1) SDHCI Capabilities_1 itself (read-only on this SoC: test 8 said NOT writable) */
	wr(CAPS1, c1 & ~UHS_MASK);
	n = rd(CAPS1);
	puts16("nouhs: [0x44] caps1 now "); hex(n); puts16("\n");
	if (n & UHS_MASK) {
		/* 2) sdhci-msm v5 vendor shadow CORE_VENDOR_SPEC_CAPABILITIES1 (0x220); writing it
		 *    replaces what Capabilities_1 reads back. Write the wanted caps1 value. */
		wr(VCAPS1, c1 & ~UHS_MASK);
		n = rd(CAPS1);
		puts16("nouhs: [0x220] caps1 now "); hex(n);
		puts16(" 0x220 "); hex(rd(VCAPS1)); puts16("\n");
	}
	puts16((n & UHS_MASK) ? "nouhs: RESULT UHS STILL ON\n" : "nouhs: RESULT UHS OFF\n");
out:
	st->bs->stall(8000000);
	return 0;
}
