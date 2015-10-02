.PHONY: all clean distclean

NODE_DIR := node_modules
NPM_BIN := $(NODE_DIR)/.bin
COFFEE_CC := $(NPM_BIN)/coffee
DEPS := $(COFFEE_CC)

in := $(wildcard *.coffee)
out := $(patsubst %.coffee,%.js,$(in))

all: $(out)

%.js: %.coffee $(COFFEE_CC)
	$(COFFEE_CC) -bc --no-header $<

clean:
	rm -f $(out)

distclean: clean
	rm -rf $(NODE_DIR)

$(DEPS):
	npm install
