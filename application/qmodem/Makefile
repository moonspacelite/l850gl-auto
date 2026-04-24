include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

# Include unified version
include ../../version.mk

PKG_NAME:=qmodem
PKG_RELEASE:=$(QMODEM_RELEASE)
PKG_VERSION:=$(QMODEM_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  PKGARCH:=all
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=QModem scripts
  DEPENDS:=	\
  		+kmod-usb2 +kmod-usb3 \
		+kmod-usb-serial +kmod-usb-serial-option +kmod-usb-serial-qualcomm \
		+kmod-usb-net +kmod-usb-acm \
		+kmod-usb-wdm \
		+kmod-usb-net-cdc-ether \
		+kmod-usb-net-cdc-mbim \
		+kmod-usb-net-rndis \
		+kmod-usb-net-cdc-ncm +kmod-usb-net-huawei-cdc-ncm \
  		+ubus-at-daemon +tom_modem +terminfo +sms-tool_q \
		+umbim \
		+conntrack \
		+jq +bc\
		+coreutils +coreutils-stat \
		+usbutils \
		+PACKAGE_luci-app-qmodem_INCLUDE_rdisc6:rdisc6 \
		+PACKAGE_luci-app-qmodem_INCLUDE_ndisc6:ndisc6 \
		+PACKAGE_luci-app-qmodem_INCLUDE_generic-qmi-wwan:kmod-usb-net-qmi-wwan
endef

define Package/$(PKG_NAME)/description
	QModem scripts (L850GL build)
endef

define Build/Prepare
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
		$(CP) ./files/* $(1)/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
