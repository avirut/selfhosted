# adapted from https://github.com/MaastrichtU-IDS/code-server/blob/main/Dockerfile

FROM codercom/code-server:4.23.1-debian

USER root

RUN apt-get update -y && apt-get upgrade -y && apt-get install -y curl

RUN chown -R 1000:1000 /opt
USER 1000

ENV CONDA_DIR=/opt/conda \
    SHELL=/bin/bash \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 
ENV PATH="${CONDA_DIR}/bin:${PATH}"

RUN export download_url=$(curl -s https://api.github.com/repos/conda-forge/miniforge/releases/latest | grep browser_download_url | grep -P "Mambaforge-\d+((\.|-)\d+)*-Linux-x86_64.sh" | grep -v sha256 | cut -d '"' -f 4) && \
    echo "Downloading latest miniforge from $download_url" && \
    curl -Lf -o miniforge.sh $download_url && \
    /bin/bash "miniforge.sh" -f -b -p "${CONDA_DIR}" && \
    rm "miniforge.sh" && \
    conda config --system --set auto_update_conda false && \
    conda config --system --set show_channel_urls true

RUN code-server --install-extension ms-python.python \
            --install-extension foam.foam-vscode \
            --install-extension quarto.quarto \
            --install-extension qwtel.sqlite-viewer \
            --install-extension monokai.theme-monokai-pro-vscode

RUN mkdir -p /home/coder/project

COPY --chown=1000 settings.json /home/coder/.local/share/code-server/User/settings.json

# Fix permission issues when editing settings.json?
# RUN chmod 777 /home/coder/.local/share/code-server/User/settings.json

RUN mamba init
RUN sudo echo "export PATH=/opt/conda/bin:\${PATH}" >> ~/.bashrc
RUN sudo echo "mamba activate" >> ~/.bashrc
WORKDIR /home/coder/project