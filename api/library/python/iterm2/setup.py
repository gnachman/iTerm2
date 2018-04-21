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
          'websocket',
      ],
      include_package_data=True,
      zip_safe=False)

