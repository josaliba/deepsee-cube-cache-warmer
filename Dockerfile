ARG IRIS_IMAGE=containers.intersystems.com/intersystems/irishealth:latest-em
FROM ${IRIS_IMAGE}

USER root

RUN mkdir -p /opt/disease-registry/docker /workspace/src /workspace/tests /workspace/packages \
    && chown -R ${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} \
       /opt/disease-registry /workspace

COPY --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} docker/ /opt/disease-registry/docker/
COPY --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} src/ /workspace/src/
COPY --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} tests/ /workspace/tests/
COPY --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} packages/ /workspace/packages/

RUN chmod 0755 /opt/disease-registry/docker/bootstrap.sh

WORKDIR /workspace
USER ${ISC_PACKAGE_MGRUSER}
