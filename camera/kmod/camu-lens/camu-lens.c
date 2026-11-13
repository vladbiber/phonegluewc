// SPDX-License-Identifier: GPL-2.0
/*
 * Nothing Phone (1) ultra-wide (s5kjn1) lens: DW9800-family VCM at 0x0c on the sensor's CCI bus.
 * The board DT has the supply (vreg_camu_vaf_1p8) but no actuator node, so this binds by path
 * and exposes one parameter: pos = -1 (powered off) or 0..1023 (DAC code).
 */
#include <linux/delay.h>
#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/regulator/consumer.h>

#define LENS_ADDR	0x0c
#define REG_INFO	0x00
#define REG_CONTROL	0x02	/* 1 shutdown, 2 ringing control */
#define REG_VCM_MSB	0x03
#define REG_MODE	0x06
#define REG_PRESCALE	0x07
#define INFO_DW9800	0xf2

static struct regulator *vaf;
static struct i2c_adapter *bus;
static int pos = -1;
static DEFINE_MUTEX(lock);

static int lens_write(const u8 *buf, int len)
{
	struct i2c_msg msg = { .addr = LENS_ADDR, .len = len, .buf = (u8 *)buf };
	int ret = i2c_transfer(bus, &msg, 1);

	return ret == 1 ? 0 : ret < 0 ? ret : -EIO;
}

static int lens_reg(u8 reg, u8 val)
{
	u8 buf[2] = { reg, val };

	return lens_write(buf, 2);
}

static int lens_on(void)
{
	u8 reg = REG_INFO, id = 0;
	struct i2c_msg msgs[2] = {
		{ .addr = LENS_ADDR, .len = 1, .buf = &reg },
		{ .addr = LENS_ADDR, .flags = I2C_M_RD, .len = 1, .buf = &id },
	};
	int ret = regulator_enable(vaf);

	if (ret)
		return ret;
	usleep_range(5000, 6000);
	lens_reg(REG_CONTROL, 0);	/* first write only wakes the chip */
	usleep_range(200, 400);
	ret = lens_reg(REG_CONTROL, 0);
	if (!ret && (i2c_transfer(bus, msgs, 2) != 2 || id != INFO_DW9800))
		ret = -ENODEV;
	/* same setup as mainline dw9719.c uses for the dw9800k: SAC mode 1, prescale 0x10 */
	if (!ret)
		ret = lens_reg(REG_CONTROL, 2);
	if (!ret)
		ret = lens_reg(REG_MODE, 1 << 6);
	if (!ret)
		ret = lens_reg(REG_PRESCALE, 0x10);
	if (ret)
		regulator_disable(vaf);
	return ret;
}

static int pos_set(const char *val, const struct kernel_param *kp)
{
	int want, ret = kstrtoint(val, 0, &want);

	if (ret)
		return ret;
	if (want < -1 || want > 1023)
		return -EINVAL;
	mutex_lock(&lock);
	if (want < 0) {
		if (pos >= 0) {
			lens_reg(REG_CONTROL, 1);
			regulator_disable(vaf);
		}
	} else {
		u8 buf[3] = { REG_VCM_MSB, want >> 8, want & 0xff };

		if (pos < 0)
			ret = lens_on();
		if (!ret) {
			ret = lens_write(buf, 3);
			if (ret && pos < 0)
				regulator_disable(vaf);
		}
	}
	if (!ret)
		pos = want;
	mutex_unlock(&lock);
	return ret;
}

static const struct kernel_param_ops pos_ops = { .set = pos_set, .get = param_get_int };
module_param_cb(pos, &pos_ops, &pos, 0664);
MODULE_PARM_DESC(pos, "-1 off, 0..1023 lens DAC code");

static int __init camu_lens_init(void)
{
	struct device_node *np = of_find_node_by_path("/soc@0/cci@ac4b000/i2c-bus@0");

	if (!np)
		return -ENODEV;
	bus = of_find_i2c_adapter_by_node(np);
	of_node_put(np);
	if (!bus)
		return -EPROBE_DEFER;
	vaf = regulator_get(NULL, "vreg_camu_vaf_1p8");
	if (IS_ERR(vaf)) {
		put_device(&bus->dev);
		return PTR_ERR(vaf);
	}
	return 0;
}

static void __exit camu_lens_exit(void)
{
	if (pos >= 0) {
		lens_reg(REG_CONTROL, 1);
		regulator_disable(vaf);
	}
	regulator_put(vaf);
	put_device(&bus->dev);
}

module_init(camu_lens_init);
module_exit(camu_lens_exit);
MODULE_DESCRIPTION("Nothing Phone (1) ultra-wide lens actuator");
MODULE_LICENSE("GPL");
