FROM pyushkevich/tk:2023a  AS base

ENV FLYWHEEL=/flywheel/v0
WORKDIR ${FLYWHEEL}

# Aloha brought in via the gear's run command
ENV ALOHA_ROOT=${FLYWHEEL}/aloha
ENV PATH=${FLYWHEEL}/flywheel/bin:/tk/greedy/build:/tk/cmrep/build:/tk/c3d/build:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${ALOHA_ROOT}/scripts:${ALOHA_ROOT}/aloha/ext/Linux/bin
ENV PYTHONPATH=${FLYWHEEL}/flywheel/lib

RUN apt update
RUN apt full-upgrade -y
RUN apt install -y libopenblas-dev bc libxt6 jq csvkit

COPY requirements.txt ${FLYWHEEL}/
RUN pip install -r requirements.txt

COPY				   \
	aloha_qc_qsub.sh	   \
	config.test.json	   \
	downloadInputFiles         \
	run			   \
	${FLYWHEEL}/

RUN cd ${FLYWHEEL}; git clone https://github.com/brainsciencecenter/flywheel.git; cd flywheel; git config pull.rebase false; git pull

RUN chmod +x run
ENTRYPOINT ["./run -v"]
