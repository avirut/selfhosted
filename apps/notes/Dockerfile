# ARG BASE_VERSION=4.23.1

# FROM codercom/code-server:${BASE_VERSION}-debian AS base

# install miniforge
# RUN wget -O Miniforge3.sh "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"
# RUN bash Miniforge3.sh -b -p "${HOME}/conda"

# RUN sudo chsh -s /bin/bash $(whoami)
# RUN "source \"${HOME}/conda/etc/profile.d/conda.sh\""
# RUN source "${HOME}/conda/etc/profile.d/mamba.sh"
# RUN conda activate

# RUN . ${HOME}/conda/etc/profile.d/conda.sh
# RUN . ${HOME}/conda/etc/profile.d/mamba.sh
# RUN mamba activate

# RUN ["/bin/bash", "-c", "source \"${HOME}/conda/etc/profile.d/conda.sh\""]
# RUN ["/bin/bash", "-c", "source \"${HOME}/conda/etc/profile.d/mamba.sh\""]
# RUN ["/bin/bash", "-c", "conda activate"]

FROM condaforge/miniforge3:24.3.0-0

ENV VERSION 4.23.1

RUN ["/bin/bash", "-c", "apt-get -y update; apt-get -y install curl"]

# RUN mkdir -p ~/.local/lib ~/.local/bin
# RUN curl -fL https://github.com/coder/code-server/releases/download/v$VERSION/code-server-$VERSION-linux-amd64.tar.gz | tar -C ~/.local/lib -xz
# RUN mv ~/.local/lib/code-server-$VERSION-linux-amd64 ~/.local/lib/code-server-$VERSION
# RUN ln -s ~/.local/lib/code-server-$VERSION/bin/code-server ~/.local/bin/code-server
# ENTRYPOINT ["/root/.local/bin/code-server"]

RUN export VERSION=4.23.1 \
 && curl -fsSL https://code-server.dev/install.sh | sh \
 && rm -rf "${HOME}/.cache"

ENTRYPOINT ["tail", "-f", "/dev/null"]

# RUN ["/bin/bash", "-c", "curl -fOL https://github.com/coder/code-server/releases/download/v${VERSION}/code-server_${VERSION}_amd64.deb"]
# RUN ["/bin/bash", "-c", "dpkg -i code-server_${VERSION}_amd64.deb"]
# RUN ["/bin/bash", "-c", "systemctl enable --now code-server@$USER"]