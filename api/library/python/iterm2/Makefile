generate: force
	make iterm2/profile.py
	make iterm2/binding.py
	make iterm2/mainmenu.py

install-local: force
	python3 setup.py install

docs: force
	cd docs && ./build.sh && open _build/html/index.html

force:

upload: force
	rm -f dist/*
	python3 setup.py bdist_wheel
	python3 setup.py sdist
	twine upload dist/*

mypy: force
	mypy --ignore-missing-imports ./test.py

pylint: force
	pylint --load-plugins=pylint_protobuf iterm2

iterm2/profile.py: force
	./gen_profile.py > iterm2/profile.py

iterm2/binding.py: force
	./gen_binding.py > iterm2/binding.py

iterm2/mainmenu.py: force
	./gen_mainmenu.py > iterm2/mainmenu.py
