FROM python:3.14.5

WORKDIR /usr/src/script
COPY ./ /usr/src/script
RUN pip install  --progress-bar off -r /usr/src/script/requirements.txt 
CMD ["python", "/usr/src/script/main.py"]
