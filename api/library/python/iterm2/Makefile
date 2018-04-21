PYTHON=python3.6

install-local: force
	${PYTHON} setup.py install

docs: force
	sphinx-apidoc -o docs/ iterm2
	cd docs && make html

force:

update: force
	${PYTHON} setup.py bdist_wheel
	${PYTHON} setup.py sdist
	twine upload dist/*
