all: force
	rm -rf SearchableComboListView.framework
	xcodebuild -target SearchableComboListView -configuration Release 'CONFIGURATION_BUILD_DIR=$$(SRCROOT)/Build/$$(CONFIGURATION)'
	mv build/Release/SearchableComboListView.framework .

force:
