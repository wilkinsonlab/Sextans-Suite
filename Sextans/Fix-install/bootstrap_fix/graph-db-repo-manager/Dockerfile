FROM python:3.8

WORKDIR /usr/src/script
COPY ./ /usr/src/script
RUN pip install  --progress-bar off -r /usr/src/script/requirements.txt

# Run as a non-root, unprivileged user. main.py writes config.ttl into its CWD,
# so it needs write access here.
RUN useradd -u 1000 -m repomanager && chown -R repomanager:repomanager /usr/src/script
USER repomanager

CMD ["python", "/usr/src/script/main.py"]
