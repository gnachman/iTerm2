from setuptools import setup

def readme():
  with open('README.rst') as f:
    return f.read()


setup(name='iterm2',
      version='0.1',
      description='Python interface to iTerm2\'s scripting API',
      long_description=readme(),
      classifiers=[
        'Development Status :: 3 - Alpha',
        'License :: OSI Approved :: GNU General Public License v3 or later (GPLv3+)',
        'Programming Language :: Python :: 2.7',
      ],
      url='http://github.com/gnachman/iTerm2',
      author='George Nachman',
      author_email='gnachman@gmail.com',
      license='GPLv3',
      packages=['iterm2'],
      install_requires=[
          'protobuf',
          'websocket-client',
      ],
      include_package_data=True,
      zip_safe=False)

