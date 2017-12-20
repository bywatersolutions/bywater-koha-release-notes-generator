FROM perl:5.26

LABEL maintainer="kyle@bywatersolutions.com"

ENV DEBUG 0
ENV PERL5LIB /app/local/lib/perl5/:/app/local/lib/perl5/x86_64-linux-gnu/
ENV KOHACLONE /kohaclone
# docker run --mount type=bind,source=/Users/kylehall/kohaclone,target=/kohaclone relnotes

WORKDIR /app
ADD . /app

RUN apt-get -y update \
    && apt-get -y install \
    git-core \
    libssl-dev \
    libmodern-perl-perl \
    libfile-slurp-perl \
    librest-client-perl \
    libjson-perl \
    libtemplate-perl \
    libcrypt-ssleay-perl \
    liblwp-protocol-https-perl
#RUN cpanm Carton
#RUN carton install

# Use shell form
CMD ./generate_release_notes.pl
