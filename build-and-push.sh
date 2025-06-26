#!/bin/bash

# Build and Push Beta9 Images to GitHub Container Registry
# Usage: ./build-and-push.sh [tag] [--build-only]

set -e

# Parse arguments
BUILD_ONLY=false
TAG="0.2.0"

for arg in "$@"; do
    case $arg in
        --build-only)
            BUILD_ONLY=true
            shift
            ;;
        *)
            if [[ ! $arg == --* ]]; then
                TAG=$arg
            fi
            shift
            ;;
    esac
done

# Image base URL
REGISTRY="ghcr.io/thalesac/beta9"

if [ "$BUILD_ONLY" = true ]; then
    echo "🚀 Building Beta9 images locally with tag: $TAG"
    echo "📦 Registry: $REGISTRY (build only, no push)"
else
    echo "🚀 Building and pushing Beta9 images with tag: $TAG"
    echo "📦 Registry: $REGISTRY"
fi

# Function to build and optionally push an image
build_and_push() {
    local component=$1
    local dockerfile=$2
    local target=$3
    local image_url="$REGISTRY/$component:$TAG"
    
    echo ""
    echo "🔨 Building $component image..."
    if [ -n "$target" ]; then
        docker build -f $dockerfile -t $image_url --target $target .
    else
        docker build -f $dockerfile -t $image_url .
    fi
    
    if [ "$BUILD_ONLY" = false ]; then
        echo "📤 Pushing $component image..."
        docker push $image_url
        echo "✅ Successfully built and pushed: $image_url"
    else
        echo "✅ Successfully built locally: $image_url"
    fi
}

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Error: Docker is not running or not accessible"
    exit 1
fi

# Build and push Gateway
build_and_push "gateway" "docker/Dockerfile.gateway" "release"

# Build and push Worker  
build_and_push "worker" "docker/Dockerfile.worker" "final"

# Build and push Runner images (multiple Python versions)
echo ""
echo "🐍 Building runner images for multiple Python versions..."

# Function to build and push runner variants
build_runner_variant() {
    local variant=$1
    local target=$2
    local build_arg=$3
    local image_url="$REGISTRY/runner:$variant-$TAG"
    
    echo "🔨 Building runner variant: $variant"
    if [ -n "$build_arg" ]; then
        docker build -f docker/Dockerfile.runner --target $target --build-arg $build_arg -t $image_url .
    else
        docker build -f docker/Dockerfile.runner --target $target -t $image_url .
    fi
    
    if [ "$BUILD_ONLY" = false ]; then
        echo "📤 Pushing runner variant: $variant"
        docker push $image_url
        echo "✅ Successfully built and pushed: $image_url"
    else
        echo "✅ Successfully built locally: $image_url"
    fi
}

# Build standard Python variants
for version in py312 py311 py310 py39 py38; do
    build_runner_variant "$version" "$version" ""
done

# Build Micromamba variants
for version in "3.12" "3.11" "3.10" "3.9" "3.8"; do
    variant="micromamba${version/./}"  # Convert 3.12 to micromamba312
    build_runner_variant "$variant" "micromamba" "PYTHON_VERSION=$version"
done

echo ""
if [ "$BUILD_ONLY" = true ]; then
    echo "🎉 All images built locally successfully!"
else
    echo "🎉 All images built and pushed successfully!"
fi
echo ""
echo "📋 Summary:"
echo "  - Gateway: $REGISTRY/gateway:$TAG"
echo "  - Worker:  $REGISTRY/worker:$TAG"
echo "  - Runner variants:"
echo "    * Standard Python: py312, py311, py310, py39, py38"
echo "    * Micromamba: micromamba312, micromamba311, micromamba310, micromamba39, micromamba38"
echo ""
if [ "$BUILD_ONLY" = false ]; then
    echo "💡 To use these images in your Helm chart, make sure the values.yaml is configured with:"
    echo "  gateway.image.registry: ghcr.io"
    echo "  gateway.image.repository: thalesac/beta9/gateway"
    echo "  gateway.image.tag: $TAG"
    echo "  worker.image.registry: ghcr.io"
    echo "  worker.image.repository: thalesac/beta9/worker"
    echo "  worker.image.tag: $TAG"
    echo "  config.imageService.runner.baseImageRegistry: ghcr.io"
    echo "  config.imageService.runner.baseImageRepository: thalesac/beta9/runner"
    echo "  config.imageService.runner.baseImageTag: $TAG"
else
    echo "💡 To push these images later, run: ./build-and-push.sh $TAG"
fi 