all: force
	rm -rf SearchableComboListView.framework
	xcodebuild -target SearchableComboListView -configuration Release
	mv build/Release/SearchableComboListView.framework .

force:
