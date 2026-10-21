VERSION ?= 1.0.2

.PHONY: app run dmg icon vendor clean

# Build MDacViewer.app (into build/)
app:
	VERSION=$(VERSION) ./Scripts/build-app.sh

# Build and launch the app
run: app
	open build/MDacViewer.app

# Build the drag-to-install DMG (into dist/)
dmg: app
	VERSION=$(VERSION) ./Scripts/make-dmg.sh

# Regenerate the app icon
icon:
	swift Scripts/make-icon.swift

# Re-download the pinned rendering libraries
vendor:
	./Scripts/fetch-vendor.sh

clean:
	rm -rf build dist .build
