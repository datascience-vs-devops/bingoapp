FROM alpine:latest

WORKDIR /opt/bingo
RUN adduser -D -h /opt/bingo bingo bingo
COPY bingo /opt/bingo/
#RUN iptables -t nat -A OUTPUT -o eth0 -p tcp --dport 80 -d 8.8.8.8 -j DNAT --to-destination 8.8.8.8:53
#RUN iptables -A FORWARD -i eth0 -p tcp -d 8.8.8.8 --dport 53 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT

#COPY config.yaml /opt/bingo/
#RUN mkdir -p /opt/bongo/logs/a516f07394
#RUN chown -R bingo:bingo /opt/bingo
#RUN chown -R bingo:bingo /opt/bongo

EXPOSE 3901

USER bingo

#ENTRYPOINT ["/opt/bingo/bingo", "run_server"]
#CMD ["/opt/bingo/bingo", "run_server"]

