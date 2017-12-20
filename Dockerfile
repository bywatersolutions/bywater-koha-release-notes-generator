FROM perl:5.26

ENV DEBUG 1
ENV PERL5LIB /usr/local/perl

RUN cpanm Modern::Perl File::Slurp Data::Dumper REST::Client Mozilla::CA JSON Template

LABEL maintainer="kyle@bywatersolutions.com"

WORKDIR /app
ADD . /app

# Use shell form
CMD ls -alh /usr/local/perl
CMD ./generate_release_notes.pl >> notes.md
