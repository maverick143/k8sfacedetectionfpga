FROM python:3.7.4-buster

RUN pip install pipenv

COPY Pipfile* /app/
WORKDIR /app

ENV PYTHONUSERBASE /pyroot

RUN PIP_USER=1 PIP_IGNORE_INSTALLED=1 pipenv install --system --deploy --ignore-pipfile

COPY . /app

CMD ["python", "main.py"]