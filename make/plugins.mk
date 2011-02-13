# plugins...
# experimental, don't use yet until you know what you are doing
$(PLUGIN_DIR)/configure.ac: | $(PLUGIN_DIR)
$(PLUGIN_DIR)/configure: $(PLUGIN_DIR)/configure.ac
	cd $(PLUGIN_DIR) && ./autogen.sh

$(BUILD_TMP)/neutrino-hd-plugins:
	mkdir $@

PLUGINS_TO_BUILD = tuxcom

plugins: $(PLUGIN_DIR)/configure $(BUILD_TMP)/neutrino-hd-plugins
	cd $(BUILD_TMP)/neutrino-hd-plugins && \
		export PKG_CONFIG=$(PKG_CONFIG) && \
		export PKG_CONFIG_PATH=$(PKG_CONFIG_PATH) && \
		CC=$(TARGET)-gcc CFLAGS="$(N_CFLAGS)" CXXFLAGS="$(N_CFLAGS)" LDFLAGS="$(N_LDFLAGS)" \
		$(PLUGIN_DIR)/configure --host=$(TARGET) --build=$(BUILD) --prefix= \
			--enable-maintainer-mode --with-boxtype=$(PLATFORM) --with-target=cdk && \
		$(MAKE) SUBDIRS="$(PLUGINS_TO_BUILD)" && \
		make install SUBDIRS="$(PLUGINS_TO_BUILD)" DESTDIR=$(TARGETPREFIX)
