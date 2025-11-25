# TeleBox 一键安装脚本

## 项目简介

[TeleBox](https://github.com/TeleBoxOrg/TeleBox) 是一个现代化的 Telegram Bot 框架，基于 Node.js 开发，提供丰富的功能和易于使用的接口。

本脚本简化了 TeleBox 的部署过程，自动完成以下步骤：

- ✅ 系统环境检测和依赖安装
- ✅ Node.js 20.x 自动安装
- ✅ TeleBox 项目下载和配置
- ✅ 依赖包自动安装
- ✅ Telegram 账号登录配置
- ✅ PM2 进程守护和服务自启动

## 系统要求

- **操作系统**: Ubuntu, Debian, CentOS 等主流 Linux 发行版
- **内存**: 至少 512MB RAM
- **存储**: 至少 1GB 可用空间

## 一键安装命令
### 安装到本地
```bash
wget https://raw.githubusercontent.com/TiaraBasori/InstallTeleBox/refs/heads/main/telebox.sh -O telebox.sh && chmod +x telebox.sh && bash telebox.sh
```
### 安装到Docker容器内
Docker版本脚本作者: https://github.com/Seikolove
```bash
wget https://raw.githubusercontent.com/TiaraBasori/InstallTeleBox/refs/heads/main/docker_telebox.sh -O docker_telebox.sh && chmod +x docker_telebox.sh && bash docker_telebox.sh
```

## 安装后管理

安装完成后，您可以使用以下命令管理 TeleBox 服务：

```bash
# 查看服务状态
pm2 status telebox

# 查看实时日志
pm2 logs telebox

# 重启服务
pm2 restart telebox

# 停止服务
pm2 stop telebox
```

## 主要功能

- 🚀 **自动安装**: 全自动完成环境配置和软件安装
- 🔒 **安全登录**: 使用 screen 会话安全处理 Telegram 登录
- 📦 **依赖管理**: 自动安装所有必要的系统依赖和 Node.js 包
- 🔄 **进程守护**: 使用 PM2 确保服务持续运行
- 🔧 **易于管理**: 提供完善的服务管理功能

## 注意事项

1. 安装前请确保服务器可以正常访问 GitHub 和 Telegram 服务
2. 需要提前准备好 Telegram API ID 和 Hash , 申请地址：https://my.telegram.org/auth?to=apps
3. 建议使用非 root 用户运行安装脚本
4. 登录过程中请按照提示操作

## 故障排除

如果安装过程中遇到问题：

1. 查看安装日志获取详细错误信息
2. [在Telegram私聊我](https://t.me/Tiara_Basori)

---

**项目地址**: [https://github.com/TeleBoxDev/TeleBox](https://github.com/TeleBoxDev/TeleBox)  
**脚本维护**: [TiaraBasori/InstallTeleBox](https://github.com/TiaraBasori/InstallTeleBox)
