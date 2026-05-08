FROM mcr.microsoft.com/dotnet/sdk:10.0.203 AS build
WORKDIR /src
COPY . .
RUN dotnet publish src/Hosts/WoodOps.Host.Api/WoodOps.Host.Api.csproj \
    -c Release \
    -o /app/publish \
    /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0.2 AS runtime
WORKDIR /app
USER app
EXPOSE 8080
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "WoodOps.Host.Api.dll"]