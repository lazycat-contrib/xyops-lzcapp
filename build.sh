#!/bin/bash
set -e

# xyOps - LazyCat App Build Script
# ============================================================

APP_NAME="xyOps"
APP_PACKAGE="cloud.lazycat.app.xyops"
APP_VERSION="1.0.0"
MANIFEST_FILE="lzc-manifest.yml"
BUILD_FILE="lzc-build.yml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================
# Check required files
# ============================================================
check_files() {
    print_info "检查必要文件..."
    local missing=0

    for f in "$MANIFEST_FILE" "$BUILD_FILE"; do
        if [ -f "$f" ]; then
            print_success "$f"
        else
            print_error "$f 不存在"
            missing=1
        fi
    done

    if [ ! -f "icon.png" ]; then
        print_warning "icon.png 不存在，请提供 512x512 PNG 图标"
        missing=1
    else
        print_success "icon.png"
    fi

    return $missing
}

# ============================================================
# Show app info
# ============================================================
show_info() {
    echo ""
    echo "============================================================"
    echo "  $APP_NAME - 应用信息"
    echo "============================================================"
    echo "  包名:    $APP_PACKAGE"
    echo "  版本:    $APP_VERSION"
    echo "  镜像:    ghcr.io/pixlcore/xyops:latest"
    echo "  端口:    5522 (Web UI), 5523 (TCP)"
    echo "  数据:    /lzcapp/var/data → /opt/xyops/data"
    echo "  特殊:    Docker Socket, init 进程"
    echo "============================================================"
    echo ""
    check_files || true
}

# ============================================================
# Build LPK package
# ============================================================
build_app() {
    print_info "构建 LPK 包..."

    if ! check_files; then
        print_error "缺少必要文件，无法构建"
        return 1
    fi

    local output="${APP_PACKAGE}-${APP_VERSION}.lpk"
    lzc-cli project build -o "$output"

    if [ $? -eq 0 ]; then
        print_success "构建成功: $output"
        ls -lh "$output"
    else
        print_error "构建失败"
        return 1
    fi
}

# ============================================================
# Copy image to LazyCat registry
# ============================================================
copy_image() {
    print_info "检查登录状态..."
    if ! lzc-cli appstore my-images &>/dev/null 2>&1; then
        print_warning "未登录懒猫应用商店"
        print_info "请先执行: lzc-cli appstore login"
        return 1
    fi

    local original_image="ghcr.io/pixlcore/xyops:latest"
    print_info "复制镜像: $original_image"

    local result
    result=$(lzc-cli appstore copy-image "$original_image" 2>&1)
    echo "$result"

    local new_image
    new_image=$(echo "$result" | grep "^uploaded:" | awk '{print $NF}')

    if [ -z "$new_image" ]; then
        print_error "镜像复制失败，未获取到新镜像地址"
        return 1
    fi

    print_success "新镜像: $new_image"
    update_manifest_image "$new_image" "$original_image"
}

# ============================================================
# Update manifest with new image
# ============================================================
update_manifest_image() {
    local new_image="$1"
    local original_image="$2"

    print_info "更新 manifest 中的镜像地址..."

    for manifest in lzc-manifest.yml manifest.yml; do
        if [ -f "$manifest" ]; then
            # Add comment with original image and replace with new
            sed -i.bak "s|image: ${original_image}|# ${original_image}\n    image: ${new_image}|g" "$manifest"
            rm -f "${manifest}.bak"
            print_success "已更新 $manifest"
        fi
    done
}

# ============================================================
# Publish to app store
# ============================================================
publish_app() {
    print_info "检查登录状态..."
    if ! lzc-cli appstore my-images &>/dev/null 2>&1; then
        print_warning "未登录懒猫应用商店"
        print_info "请先执行: lzc-cli appstore login"
        return 1
    fi

    local lpk_file="${APP_PACKAGE}-${APP_VERSION}.lpk"
    if [ ! -f "$lpk_file" ]; then
        print_error "找不到 $lpk_file，请先构建"
        return 1
    fi

    print_info "发布到应用商店: $lpk_file"
    lzc-cli appstore publish "$lpk_file"

    if [ $? -eq 0 ]; then
        print_success "发布成功，等待审核 (1-3 天)"
    else
        print_error "发布失败"
        return 1
    fi
}

# ============================================================
# One-click workflow
# ============================================================
one_click_publish() {
    echo ""
    print_info "=== 阶段 1: 初始构建 ==="
    build_app || return 1

    echo ""
    print_info "=== 阶段 2: 镜像复制 + 更新 manifest ==="
    copy_image || return 1

    echo ""
    print_info "=== 阶段 3: 重新构建（新镜像）==="
    build_app || return 1

    echo ""
    print_info "=== 阶段 4: 发布到应用商店 ==="
    publish_app || return 1

    echo ""
    print_success "全部完成！"
}

# ============================================================
# Main menu
# ============================================================
main() {
    echo ""
    echo "============================================================"
    echo "  $APP_NAME - 懒猫应用构建工具"
    echo "============================================================"
    echo "  1. 构建应用 (Build)"
    echo "  2. 镜像复制到懒猫仓库 (Copy Image)"
    echo "  3. 发布到应用商店 (Publish)"
    echo "  4. 一键构建+镜像复制+发布 (One-Click)"
    echo "  5. 查看应用信息 (Info)"
    echo "  6. 退出"
    echo "============================================================"
    echo ""
    read -p "请选择 [1-6]: " choice

    case $choice in
        1) build_app ;;
        2) copy_image ;;
        3) publish_app ;;
        4) one_click_publish ;;
        5) show_info ;;
        6) exit 0 ;;
        *) print_error "无效选择" ;;
    esac
}

main "$@"
