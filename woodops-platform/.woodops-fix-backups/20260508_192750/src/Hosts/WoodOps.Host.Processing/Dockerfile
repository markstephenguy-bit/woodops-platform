FROM mcr.microsoft.com/dotnet/sdk:10.0.203 AS build
WORKDIR /src
COPY . .
RUN dotnet publish src/Hosts/WoodOps.Host.Processing/WoodOps.Host.Processing.csproj \
    -c Release \
    -o /app/publish \
    /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/runtime:10.0.2 AS runtime
WORKDIR /app
USER app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "WoodOps.Host.Processing.dll"]