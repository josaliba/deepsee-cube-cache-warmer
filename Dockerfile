ARG IRIS_IMAGE=containers.intersystems.com/intersystems/iris-community:latest-em
FROM ${IRIS_IMAGE}

USER root

RUN mkdir -p /opt/disease-registry/docker /workspace/src /workspace/tests /workspace/packages \
    && chown -R ${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} \
       /opt/disease-registry /workspace

COPY --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} docker/ /opt/disease-registry/docker/
COPY --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} module.xml /workspace/module.xml
COPY --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} src/ /workspace/src/
COPY --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} tests/ /workspace/tests/
COPY --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} packages/ /workspace/packages/

RUN chmod 0755 /opt/disease-registry/docker/bootstrap.sh

WORKDIR /workspace
USER ${ISC_PACKAGE_MGRUSER}

# Install InterSystems Package Manager (IPM) into the image so the demo can
# load the cache warmer through its module.xml exactly as end users would.
RUN iris start IRIS \
    && iris session IRIS < /opt/disease-registry/docker/install-ipm.script \
    && iris stop IRIS quietly
