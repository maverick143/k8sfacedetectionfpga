FROM xilinx-ml-suite-ubuntu-16.04-xrt-2018.2-caffe-mls-1.4:latest

USER root
WORKDIR /opt/ml-suite
COPY files/* /opt/ml-suite/
COPY camworker-0.1-py2-none-any.whl .
RUN pip install camworker-0.1-py2-none-any.whl
USER mluser
CMD ["/bin/bash", "-c", "source /opt/ml-suite/overlaybins/setup.sh && camworker"]
