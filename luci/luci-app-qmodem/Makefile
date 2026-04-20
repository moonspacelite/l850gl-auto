# Copyright (C) 2024 Tom <fjrcn@outlook.com>
# This is free software, licensed under the GNU General Public License v3.

include $(TOPDIR)/rules.mk

# Include unified version
include ../../version.mk

PKG_NAME:=luci-app-qmodem
LUCI_TITLE:=LuCI support for QWRT Modem (L850GL)
LUCI_PKGARCH:=all
PKG_VERSION:=$(QMODEM_VERSION)
PKG_RELEASE:=$(QMODEM_RELEASE)
PKG_LICENSE:=GPLv3
PKG_LINCESE_FILES:=LICENSE
PKG_MAINTAINER:=Tom <fjrcn@outlook.com>
LUCI_DEPENDS:=+luci-compat \
		+qmodem 


define Package/luci-app-qmodem/conffiles
/etc/config/qmodem
endef

define Package/luci-app-qmodem/config

choice
  prompt "IPv6 Neighbor Discovery Selection"
  default PACKAGE_luci-app-qmodem_INCLUDE_ndisc6

  config PACKAGE_luci-app-qmodem_INCLUDE_ndisc6
  bool "Include ndisc6 for IPv6 Neighbor Discovery"

  config PACKAGE_luci-app-qmodem_INCLUDE_rdisc6
  bool "Include rdisc6 for IPv6 Router Discovery"

  config PACKAGE_luci-app-qmodem_INCLUDE_no_ndisc_rdisc6
  bool "Do not include any IPv6 Neighbor/Router Discovery tool"
endchoice

	config PACKAGE_luci-app-qmodem_INCLUDE_generic-qmi-wwan
		bool "Include generic QMI WWAN driver"
		default y

endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
