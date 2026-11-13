// SPDX-License-Identifier: GPL-2.0-only
/*
 * Minimal FF_RUMBLE driver for the Qualcomm PM8350B/PM7325B HV haptics block
 * (Nothing Phone (1)). Register layout from the downstream qcom-hv-haptics.c.
 * Plays DIRECT_PLAY (constant amplitude, LRA auto-resonance on).
 */
#include <linux/input.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include <linux/regmap.h>
#include <linux/delay.h>

#define HAP_CFG_REVISION2		0x01
#define HAP_CFG_STATUS_DATA_MSB		0x09
#define HAP_CFG_STATUS_DATA_LSB		0x0a
#define HAP_CFG_FAULT_STATUS		0x0c
#define HAP_CFG_EN_CTL			0x46
#define  HAPTICS_EN			BIT(7)
#define HAP_CFG_VMAX			0x48
#define  VMAX_STEP_MV			50
#define HAP_CFG_DRV_WF_SEL		0x49
#define  DRV_WF_FMT			BIT(4)
#define  DRV_WF_SEL_MASK		GENMASK(1, 0)
#define  WF_SINE			1
#define HAP_CFG_SPMI_PLAY		0x4c
#define  PLAY_EN			BIT(7)
#define  SRC_DIRECT_PLAY		1
#define HAP_CFG_TLRA_OL_HIGH		0x5c
#define  TLRA_STEP_US			5
#define HAP_CFG_AUTORES_CFG		0x63
#define  AUTORES_EN			BIT(7)
#define HAP_CFG_FAULT_CLR		0x66
#define  FAULT_CLR_ALL			(BIT(2) | BIT(1) | BIT(0))
#define HAP_CFG_VSET_CFG		0x68
#define  FORCE_VREG_RDY			BIT(0)
#define HAP_CFG_MOD_STATUS_SEL		0x70
#define HAP_CFG_MOD_STATUS_XT		0x71
#define HAP_CFG_CAL_EN			0x72
#define  CAL_RC_CLK_MASK		GENMASK(3, 2)
#define  CAL_RC_CLK_AUTO		(1 << 2)

#define HAP_PTN_DIRECT_PLAY		0x26

#define HAP_BOOST_STATUS4		0x0b
#define HAP_BOOST_HW_CTRL_FOLLOW	0x41
#define HAP_BOOST_VREG_EN		0x46

static unsigned int vmax_mv = 3600;
module_param(vmax_mv, uint, 0644);
MODULE_PARM_DESC(vmax_mv, "peak drive voltage at full rumble (mV, max 9150)");
static unsigned int lra_period_us = 5880;
module_param(lra_period_us, uint, 0444);
static bool debug;
module_param(debug, bool, 0644);

struct hvhap {
	struct device *dev;
	struct regmap *map;
	struct input_dev *input;
	struct work_struct work;
	u32 cfg, ptn, hbst;
	int level;		/* 0..255 */
	bool playing;
};

static int hap_w(struct hvhap *h, u32 base, u32 reg, u8 val)
{
	return regmap_write(h->map, base + reg, val);
}

static int hap_u(struct hvhap *h, u32 base, u32 reg, u8 mask, u8 val)
{
	return regmap_update_bits(h->map, base + reg, mask, val);
}

static void hap_dump(struct hvhap *h, const char *when)
{
	unsigned int en, vmax, play, fault, sts_m, sts_l, bvreg, bfollow, bsts;

	regmap_read(h->map, h->cfg + HAP_CFG_EN_CTL, &en);
	regmap_read(h->map, h->cfg + HAP_CFG_VMAX, &vmax);
	regmap_read(h->map, h->cfg + HAP_CFG_SPMI_PLAY, &play);
	regmap_read(h->map, h->cfg + HAP_CFG_FAULT_STATUS, &fault);
	unsigned int cl_m, cl_l;

	hap_w(h, h->cfg, HAP_CFG_MOD_STATUS_XT, 0);
	hap_w(h, h->cfg, HAP_CFG_MOD_STATUS_SEL, 5);	/* HAP_DRV_STS */
	regmap_read(h->map, h->cfg + HAP_CFG_STATUS_DATA_MSB, &sts_m);
	regmap_read(h->map, h->cfg + HAP_CFG_STATUS_DATA_LSB, &sts_l);
	hap_w(h, h->cfg, HAP_CFG_MOD_STATUS_SEL, 0);	/* CAL_TLRA_CL_STS: resonance seen by auto-res */
	regmap_read(h->map, h->cfg + HAP_CFG_STATUS_DATA_MSB, &cl_m);
	regmap_read(h->map, h->cfg + HAP_CFG_STATUS_DATA_LSB, &cl_l);
	regmap_read(h->map, h->hbst + HAP_BOOST_VREG_EN, &bvreg);
	regmap_read(h->map, h->hbst + HAP_BOOST_HW_CTRL_FOLLOW, &bfollow);
	regmap_read(h->map, h->hbst + HAP_BOOST_STATUS4, &bsts);
	dev_info(h->dev, "%s: cl_tlra done=%d raw=%u\n", when, !!(cl_m & BIT(5)), (cl_m & 0x1f) << 8 | cl_l);
	dev_info(h->dev, "%s: en=%#x vmax=%#x play=%#x fault=%#x drv_sts=%#x/%#x hbst vreg_en=%#x follow=%#x sts4=%#x\n",
		 when, en, vmax, play, fault, sts_m, sts_l, bvreg, bfollow, bsts);
}

static void hap_play(struct hvhap *h, int level)
{
	if (level) {
		hap_w(h, h->cfg, HAP_CFG_FAULT_CLR, FAULT_CLR_ALL);
		hap_w(h, h->cfg, HAP_CFG_VMAX, min(vmax_mv, 9150U) / VMAX_STEP_MV);
		hap_w(h, h->ptn, HAP_PTN_DIRECT_PLAY, level);
		hap_u(h, h->cfg, HAP_CFG_AUTORES_CFG, AUTORES_EN, AUTORES_EN);
		/* Nothing's RichTap build forces VREG_RDY while playing */
		hap_u(h, h->cfg, HAP_CFG_VSET_CFG, FORCE_VREG_RDY, FORCE_VREG_RDY);
		hap_w(h, h->cfg, HAP_CFG_SPMI_PLAY, PLAY_EN | SRC_DIRECT_PLAY);
		h->playing = true;
		if (debug) {
			msleep(200);
			hap_dump(h, "play");
		}
	} else if (h->playing) {
		hap_w(h, h->cfg, HAP_CFG_SPMI_PLAY, SRC_DIRECT_PLAY);
		hap_u(h, h->cfg, HAP_CFG_VSET_CFG, FORCE_VREG_RDY, 0);
		h->playing = false;
		if (debug)
			hap_dump(h, "stop");
	}
}

static void hap_work(struct work_struct *work)
{
	struct hvhap *h = container_of(work, struct hvhap, work);

	hap_play(h, READ_ONCE(h->level));
}

static int hap_ff_play(struct input_dev *dev, void *data, struct ff_effect *effect)
{
	struct hvhap *h = input_get_drvdata(dev);
	int level = effect->u.rumble.strong_magnitude >> 8;

	if (!level)
		level = effect->u.rumble.weak_magnitude >> 9;
	WRITE_ONCE(h->level, level);
	schedule_work(&h->work);
	return 0;
}

static void hap_close(struct input_dev *dev)
{
	struct hvhap *h = input_get_drvdata(dev);

	cancel_work_sync(&h->work);
	hap_play(h, 0);
}

static int hap_hw_init(struct hvhap *h)
{
	unsigned int rev, tlra = lra_period_us / TLRA_STEP_US;
	int ret;

	ret = regmap_read(h->map, h->cfg + HAP_CFG_REVISION2, &rev);
	if (ret)
		return ret;
	dev_info(h->dev, "HAP_CFG revision %u\n", rev);
	if (debug)
		hap_dump(h, "boot");

	hap_w(h, h->cfg, HAP_CFG_SPMI_PLAY, 0);
	hap_u(h, h->cfg, HAP_CFG_DRV_WF_SEL, DRV_WF_SEL_MASK | DRV_WF_FMT, WF_SINE);
	hap_u(h, h->cfg, HAP_CFG_CAL_EN, CAL_RC_CLK_MASK, CAL_RC_CLK_AUTO);
	hap_w(h, h->cfg, HAP_CFG_TLRA_OL_HIGH, (tlra >> 8) & 0xf);
	hap_w(h, h->cfg, HAP_CFG_TLRA_OL_HIGH + 1, tlra & 0xff);
	return hap_u(h, h->cfg, HAP_CFG_EN_CTL, HAPTICS_EN, HAPTICS_EN);
}

static int hap_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct hvhap *h;
	u32 reg = 0xf000;
	int ret;

	h = devm_kzalloc(dev, sizeof(*h), GFP_KERNEL);
	if (!h)
		return -ENOMEM;
	h->dev = dev;
	h->map = dev_get_regmap(dev->parent, NULL);
	if (!h->map)
		return -ENODEV;
	if (dev->of_node)
		of_property_read_u32(dev->of_node, "reg", &reg);
	h->cfg = reg;
	h->ptn = reg + 0x100;
	h->hbst = reg + 0x200;
	INIT_WORK(&h->work, hap_work);

	ret = hap_hw_init(h);
	if (ret)
		return dev_err_probe(dev, ret, "hw init failed\n");

	h->input = devm_input_allocate_device(dev);
	if (!h->input)
		return -ENOMEM;
	h->input->name = "pm8350b-haptics";
	h->input->id.version = 1;
	h->input->close = hap_close;
	input_set_drvdata(h->input, h);
	input_set_capability(h->input, EV_FF, FF_RUMBLE);
	ret = input_ff_create_memless(h->input, NULL, hap_ff_play);
	if (ret)
		return ret;
	ret = input_register_device(h->input);
	if (ret)
		return ret;
	platform_set_drvdata(pdev, h);
	return 0;
}

static void hap_remove(struct platform_device *pdev)
{
	struct hvhap *h = platform_get_drvdata(pdev);

	cancel_work_sync(&h->work);
	hap_play(h, 0);
}

static int hap_suspend(struct device *dev)
{
	struct hvhap *h = dev_get_drvdata(dev);

	cancel_work_sync(&h->work);
	hap_play(h, 0);
	return 0;
}

static DEFINE_SIMPLE_DEV_PM_OPS(hap_pm_ops, hap_suspend, NULL);

static const struct of_device_id hap_of_match[] = {
	{ .compatible = "qcom,pm8350b-haptics" },
	{ }
};
MODULE_DEVICE_TABLE(of, hap_of_match);

static struct platform_driver hap_driver = {
	.probe = hap_probe,
	.remove = hap_remove,
	.driver = {
		.name = "qcom-hv-haptics-lite",
		.pm = pm_sleep_ptr(&hap_pm_ops),
		.of_match_table = hap_of_match,
	},
};

/*
 * Without a DT node, hang a device off the PM8350B (SID 3) temp-alarm's parent so the
 * module works on an unmodified DT too.
 */
static struct platform_device *hap_fallback;

static int __init hap_init(void)
{
	struct device_node *np;
	struct platform_device *anchor;
	int ret;

	ret = platform_driver_register(&hap_driver);
	if (ret)
		return ret;

	np = of_find_compatible_node(NULL, NULL, "qcom,pm8350b-haptics");
	if (np) {
		of_node_put(np);
		return 0;
	}
	np = of_find_node_by_path("/soc@0/spmi@c440000/pmic@3/temp-alarm@a00");
	if (!np)
		return 0;
	anchor = of_find_device_by_node(np);
	of_node_put(np);
	if (!anchor)
		return 0;
	hap_fallback = platform_device_register_data(anchor->dev.parent, "qcom-hv-haptics-lite",
						     PLATFORM_DEVID_NONE, NULL, 0);
	put_device(&anchor->dev);
	if (IS_ERR(hap_fallback))
		hap_fallback = NULL;
	return 0;
}

static void __exit hap_exit(void)
{
	platform_device_unregister(hap_fallback);
	platform_driver_unregister(&hap_driver);
}

module_init(hap_init);
module_exit(hap_exit);
MODULE_DESCRIPTION("Qualcomm PM8350B HV haptics, FF_RUMBLE only");
MODULE_LICENSE("GPL");
