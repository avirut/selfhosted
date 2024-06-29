# adapted from https://github.com/MaastrichtU-IDS/code-server/blob/main/Dockerfile

FROM codercom/code-server:4.90.3-debian

# preparation
USER root
RUN apt-get update -y && apt-get upgrade -y && apt-get install -y curl ffmpeg libsm6 libxext6 libgl1-mesa-dev
RUN chown -R 1000:1000 /opt
USER 1000

# copy code-server items
COPY --chown=1000 settings.json /home/coder/.local/share/code-server/User/settings.json

# install code-server extensions
RUN code-server --install-extension ms-python.python \
            --install-extension ms-toolsai.jupyter \
            --install-extension foam.foam-vscode \
            --install-extension quarto.quarto \
            --install-extension qwtel.sqlite-viewer \
            --install-extension monokai.theme-monokai-pro-vscode

# set up for conda
ENV CONDA_DIR=/opt/conda \
    SHELL=/bin/bash \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 
ENV PATH="${CONDA_DIR}/bin:${PATH}"

# download and install miniforge
RUN export download_url=$(curl -s https://api.github.com/repos/conda-forge/miniforge/releases/latest | grep browser_download_url | grep -P "Mambaforge-\d+((\.|-)\d+)*-Linux-x86_64.sh" | grep -v sha256 | cut -d '"' -f 4) && \
    echo "Downloading latest miniforge from $download_url" && \
    curl -Lf -o miniforge.sh $download_url && \
    /bin/bash "miniforge.sh" -f -b -p "${CONDA_DIR}" && \
    rm "miniforge.sh" && \
    conda config --system --set auto_update_conda false && \
    conda config --system --set show_channel_urls true

# install quarto
RUN curl -LO https://quarto.org/download/latest/quarto-linux-amd64.deb && \
    sudo dpkg -i quarto-linux-amd64.deb && \
    rm quarto-linux-amd64.deb

RUN mkdir -p /home/coder/project

# prep terminal and conda permissions
RUN mamba init
RUN sudo echo "export PATH=/opt/conda/bin:\${PATH}" >> ~/.bashrc
RUN sudo echo "mamba activate" >> ~/.bashrc
# line below is needed if you want to use a bind mount rather than a named volume for conda envs and pkgs
# RUN chown 1000:1000 /opt/conda/envs && chown 1000:1000 /opt/conda/pkgs
WORKDIR /home/coder/project

ENTRYPOINT ["/usr/bin/entrypoint.sh", "--bind-addr", "0.0.0.0:8080", "--disable-getting-started-override", "--disable-telemetry", "."]