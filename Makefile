sourcefiles := $(wildcard static/static/js/*.coffee)
targetfiles := $(sourcefiles:.coffee=.js)


all: $(targetfiles)

%.js: %.coffee
	coffee -c $^
	
