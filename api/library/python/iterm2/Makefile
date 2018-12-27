PYTHON=python3

install-local: force
	${PYTHON} setup.py install

docs: force
	cd docs && ./build.sh && open _build/html/index.html

force:

upload: force
	rm -f dist/*
	${PYTHON} setup.py bdist_wheel
	${PYTHON} setup.py sdist
	twine upload dist/*

mypy: force
	mypy --ignore-missing-imports ./test.py
