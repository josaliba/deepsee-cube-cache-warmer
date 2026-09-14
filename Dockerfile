ARG IMAGE=intersystemsdc/iris-community:latest-em
FROM ${IMAGE}

WORKDIR /home/irisowner/dev
COPY --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} . .

# The image entrypoint initialises a USER namespace with irissqlcli on first
# start. That step fails on IRIS 2026.1 and stops the container, and everything
# it would do is done in iris.script instead, so mark it as already completed.
RUN date > ${ISC_PACKAGE_INSTALLDIR}/iris.init

RUN iris start IRIS \
 && iris session IRIS < iris.script \
 && iris stop IRIS quietly
