NAME = folonium
VERSION = 1.2.2

PKGFILE = $(NAME).kwinscript
PKGDIR = pkg

CARGO_HOME ?= $(HOME)/.cargo
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

clean: $(PKGDIR)
	rm -r $(PKGDIR)

cleanpkg: $(PKGFILE)
	rm $(PKGFILE)

cleanall: clean cleanpkg

lint: node_modules
	npx prettier --check .
	npx eslint
	npx -w docs eslint

pretty: node_modules
	npx prettier --check --write .

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

# src/index.ts is the recovered 2026-10-28 bundle from the
# "Drag and KWin engine fixes" session. Keep it verbatim: rebuilding it from
# the older per-module sources would replace it with the stale engine.
folonium.mjs: src/index.ts
	cp -f src/index.ts folonium.mjs

node_modules:
	npm ci

$(PKGDIR):
	mkdir -p $(PKGDIR)
	mkdir -p $(PKGDIR)/contents/code
	mkdir $(PKGDIR)/contents/config
	mkdir $(PKGDIR)/contents/ui

dbus:
	cd dbus-saver && cargo install --path .
	install -m 644 -D -t $(XDG_CONFIG_HOME)/systemd/user dbus-saver/folonium-saver.service
	sed -i 's|^ExecStart=folonium-saver$$|ExecStart=$(CARGO_HOME)/bin/folonium-saver|' $(XDG_CONFIG_HOME)/systemd/user/folonium-saver.service
	install -m 644 -D -t $(XDG_DATA_HOME)/dbus-1/services dbus-saver/xyz.vaughanm.folonium.service
	sed -i 's|^Exec=folonium-saver$$|Exec=$(CARGO_HOME)/bin/folonium-saver|' $(XDG_DATA_HOME)/dbus-1/services/xyz.vaughanm.folonium.service

dbus-build:
	cd dbus-saver && cargo build --release

docs: docs-build

docs-build: node_modules
	npm -w docs run build

docs-dev: node_modules
	npm -w docs run dev
