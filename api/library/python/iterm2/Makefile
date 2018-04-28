PYTHON=python3.6

install-local: force
	${PYTHON} setup.py install

docs: force
	pydoc3.6 -w iterm2
	pydoc3.6 -w iterm2.window
	pydoc3.6 -w iterm2.connection
	pydoc3.6 -w iterm2.hierarchy
	pydoc3.6 -w iterm2.notifications
	pydoc3.6 -w iterm2.profile
	pydoc3.6 -w iterm2.rpc
	pydoc3.6 -w iterm2.session
	pydoc3.6 -w iterm2.tab
	pydoc3.6 -w iterm2.tool
	pydoc3.6 -w iterm2.transaction
	pydoc3.6 -w iterm2.util
	pydoc3.6 -w iterm2.window
	mv iterm2.connection.html iterm2.hierarchy.html iterm2.notifications.html iterm2.profile.html iterm2.rpc.html iterm2.session.html iterm2.tab.html iterm2.tool.html iterm2.transaction.html iterm2.util.html iterm2.window.html docs
	mv iterm2.html docs/index.html
        # pydoc crashes on protobuf files, lol. The source code makes lovely documentation in its stead.
	echo '<pre>' > docs/iterm2.api_pb2.html
	cat ../../../../proto/api.proto >> docs/iterm2.api_pb2.html
	echo '</pre>' >> docs/iterm2.api_pb2.html
	test -d ~/iterm2-website/source/python-api && cp docs/* ~/iterm2-website/source/python-api

force:

upload: force
	rm dist/*
	${PYTHON} setup.py bdist_wheel
	${PYTHON} setup.py sdist
	twine upload dist/*
