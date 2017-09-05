install-local: force
	python setup.py install

docs: force
	sphinx-apidoc -o docs/ iterm2
	cd docs && make html

force:
