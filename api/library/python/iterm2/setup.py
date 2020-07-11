import re
from setuptools import setup

def readme():
  with open('README.rst') as f:
    return f.read()

# Load version by parsing _version.py
VERSIONFILE="iterm2/_version.py"
verstrline = open(VERSIONFILE, "rt").read()
VSRE = r"^__version__ = ['\"]([^'\"]*)['\"]"
mo = re.search(VSRE, verstrline, re.M)
if mo:
    verstr = mo.group(1)
else:
    raise RuntimeError("Unable to find version string in %s." % (VERSIONFILE,))


setup(name='iterm2',
      version=verstr,
      description='Python interface to iTerm2\'s scripting API',
      long_description=readme(),
      classifiers=[
        'Development Status :: 3 - Alpha',
        'License :: OSI Approved :: GNU General Public License v2 or later (GPLv2+)',
        'Programming Language :: Python :: 3.6',
      ],
      url='http://github.com/gnachman/iTerm2',
      author='George Nachman',
      author_email='gnachman@gmail.com',
      license='GPLv2',
      packages=['iterm2'],
      install_requires=[
          'protobuf',
          'websockets',
          'pyobjc'
      ],
      include_package_data=True,
      zip_safe=False)

