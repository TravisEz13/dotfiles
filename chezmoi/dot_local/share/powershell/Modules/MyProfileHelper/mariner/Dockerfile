FROM mcr.microsoft.com/cbl-mariner/base/core:2.0
#FROM mcr.microsoft.com/powershell:mariner-2.0
RUN tdnf makecache
RUN tdnf install -y dnf-utils
RUN dnf makecache -y
RUN tdnf install -y nano sudo powershell

RUN echo "export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false" > /etc/profile.d/dotnet_system_globalization_invariant.sh
#RUN echo "DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false" >> /etc/environment

CMD [ "/bin/sh", "-l"]
