#!/bin/bash

set -exuo pipefail

# When checking out onnxruntime using git, these would be put in cmake/external
# as submodules. We replicate that behavior using the "source"s from meta.yaml.
readonly external_dirs=( "eigen" "json" "onnx" "pytorch_cpuinfo" )
readonly external_root="cmake/external"
for external_dir in "${external_dirs[@]}"
do
    dest="${external_root}/${external_dir}"
    if [[ -e "${dest}" ]]; then
        rm -r "${dest}"
    fi
    mv "${external_dir}" "${dest}"
done

# patch eigen
cat <<EOT >> patch.py
from pathlib import Path
import re

for header_file in Path('cmake/external/eigen').rglob('*PacketMath.h'):
    file_content = header_file.open().read()
    with header_file.open("w") as fh:
        file_content = re.sub("HasExp[ ]*\=[ ]*1", "HasExp = EIGEN_FAST_MATH", file_content)
        file_content = re.sub("HasLog[ ]*\=[ ]*1", "HasLog = EIGEN_FAST_MATH", file_content)
        file_content = re.sub("HasLog1p[ ]*\=[ ]*1", "HasLog1p = EIGEN_FAST_MATH", file_content)
        file_content = re.sub("HasExpm1[ ]*\=[ ]*1", "HasExpm1 = EIGEN_FAST_MATH", file_content)
        fh.write(file_content)
EOT
python patch.py

pushd "${external_root}/SafeInt/safeint"
ln -s $PREFIX/include/SafeInt.hpp
popd

cmake_extra_defines=( "Protobuf_PROTOC_EXECUTABLE=$BUILD_PREFIX/bin/protoc" \
                      "Protobuf_INCLUDE_DIR=$PREFIX/include" \
                      "onnxruntime_PREFER_SYSTEM_LIB=ON" \
                      "onnxruntime_USE_COREML=OFF" \
                      "EIGEN_FAST_MATH=0" \
                      "CMAKE_PREFIX_PATH=$PREFIX" )

# Copy the defines from the "activate" script (e.g. activate-gcc_linux-aarch64.sh)
# into --cmake_extra_defines.
read -a CMAKE_ARGS_ARRAY <<< "${CMAKE_ARGS}"
for cmake_arg in "${CMAKE_ARGS_ARRAY[@]}"
do
    if [[ "${cmake_arg}" == -DCMAKE_SYSTEM_* ]]; then
        # Strip -D prefix
        cmake_extra_defines+=( "${cmake_arg#"-D"}" )
    fi
done


python tools/ci_build/build.py \
    --enable_lto \
    --build_dir build-ci \
    --use_full_protobuf \
    --cmake_extra_defines "${cmake_extra_defines[@]}" \
    --cmake_generator Ninja \
    --build_wheel \
    --config Release \
    --update \
    --build \
    --skip_submodule_sync

cp build-ci/Release/dist/onnxruntime-*.whl onnxruntime-${PKG_VERSION}-py3-none-any.whl
python -m pip install onnxruntime-${PKG_VERSION}-py3-none-any.whl
