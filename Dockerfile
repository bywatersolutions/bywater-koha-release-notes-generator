FROM perl:5.26

LABEL maintainer="kyle@bywatersolutions.com"

ENV DEBUG 0
ENV KOHACLONE /kohaclone
ENV UPLOAD 1
#ENV GITHUB_TOKEN
#ENV KOHA_BRANCH

WORKDIR /app
ADD . /app

RUN apt-get -y update \
    && apt-get -y install \
    git-core \
    libcrypt-ssleay-perl \
    libjson-perl \
    liblwp-protocol-https-perl \
    libmodern-perl-perl \
    librest-client-perl \
    libssl-dev \
    libtemplate-perl \
    libwww-perl

RUN git clone --origin bws-production https://github.com/bywatersolutions/bywater-koha.git $KOHACLONE

CMD ./generate_release_notes.pl
