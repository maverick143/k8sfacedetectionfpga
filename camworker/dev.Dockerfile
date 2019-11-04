# camworker image is normally built on an AMI with the correct base
# Xilinx Docker image. This file is only used for the dev instance
# of camworker which has only mock FPGA functionality.
FROM python:2.7.16-buster

RUN pip install pipenv

COPY Pipfile* /app/
WORKDIR /app

COPY . /app

RUN pip install -e /app

CMD ["camserver"]