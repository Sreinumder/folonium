NAME = folonium
VERSION = 1.2.2

PKGFILE = $(NAME).kwinscript
PKGDIR = pkg

XDG_CONFIG_HOME ?= $(HOME)/.config
XDG_DATA_HOME ?= $(HOME)/.local/share

.NOTPARALLEL: all

all: build install cleanall

build: res src
	zip -r $(PKGFILE) $(PKGDIR)

$(PKGFILE): build

install:
	kpackagetool6 -t KWin/Script -s $(NAME) \
		&& kpackagetool6 -t KWin/Script -u $(PKGFILE) \
		|| kpackagetool6 -t KWin/Script -i $(PKGFILE)
	install -m 644 -D -t $(XDG_DATA_HOME)/applications res/folonium-settings.desktop

clean:
	rm -rf $(PKGDIR)

cleanpkg:
	rm -f $(PKGFILE)

cleanall: clean cleanpkg

res: $(PKGDIR)
	cp -f res/metadata.json $(PKGDIR)/
	cp -f res/main.xml $(PKGDIR)/contents/config/
	cp -f res/config.ui $(PKGDIR)/contents/ui/
	cp -f res/main.js $(PKGDIR)/contents/code/
	sed -i "s/%VERSION%/$(VERSION)/" $(PKGDIR)/metadata.json
	sed -i "s/%NAME%/$(NAME)/" $(PKGDIR)/metadata.json

src: folonium.mjs $(PKGDIR)
	mv -f folonium.mjs $(PKGDIR)/contents/code/main.mjs
	cp -f src/qml/* $(PKGDIR)/contents/ui/

# src/index.ts is the maintained bundle; KWin loads it as contents/code/main.mjs.
# Edit it directly - there is no per-module build step.
folonium.mjs: src/index.ts
	cp -f src/index.ts folonium.mjs

$(PKGDIR):
	mkdir -p $(PKGDIR)
	mkdir -p $(PKGDIR)/contents/code
	mkdir $(PKGDIR)/contents/config
	mkdir $(PKGDIR)/contents/ui
