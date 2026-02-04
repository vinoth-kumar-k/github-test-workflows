# Multi-stage Dockerfile for ASP.NET Core Web API
# Stage 1: Build
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

# Copy csproj and restore dependencies (layer caching)
COPY ["DotNetCoreApp/DotNetCoreApp.csproj", "DotNetCoreApp/"]
RUN dotnet restore "DotNetCoreApp/DotNetCoreApp.csproj"

# Copy the rest of the source code
COPY . .
WORKDIR "/src/DotNetCoreApp"

# Build the application
RUN dotnet build "DotNetCoreApp.csproj" -c Release -o /app/build

# Stage 2: Publish
FROM build AS publish
RUN dotnet publish "DotNetCoreApp.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Stage 3: Runtime
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS runtime
WORKDIR /app

# Create a non-root user for security
RUN addgroup --system --gid 1000 appuser && \
    adduser --system --uid 1000 --ingroup appuser appuser

# Copy published output from publish stage
COPY --from=publish /app/publish .

# Change ownership to non-root user
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Expose port 8080 (non-privileged port)
EXPOSE 8080

# Configure ASP.NET Core to listen on port 8080
ENV ASPNETCORE_URLS=http://+:8080

# Health check for Kubernetes probes
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl --fail http://localhost:8080/health || exit 1

# Set entry point
ENTRYPOINT ["dotnet", "DotNetCoreApp.dll"]
