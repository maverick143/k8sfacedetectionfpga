from setuptools import setup, find_packages

NAME = "camworker"

setup(
    name=NAME,
    description="Face detection worker",
    packages=find_packages(),
    version="0.1",
    # xfdnn also required but provided by run environment
    install_requires=["numpy", "opencv-python", "redis", "msgpack"],
    entry_points={"console_scripts": ["camworker = camworker.main:main"]},
)
