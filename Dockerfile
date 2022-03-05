FROM alpine:3.15

RUN apk --no-cache --update add bash python3 py-pip groff mysql-client postgresql-client
RUN pip3 install --upgrade awscli

COPY backup.sh .

CMD /backup.sh
