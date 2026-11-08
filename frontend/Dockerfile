# --platform=$BUILDPLATFORM:npm ci 與 vite build 的產物是靜態檔,跟架構無關,多架構 build 時只在 runner 原生跑一次;
# 只有最後的 nginx stage(純複製檔案)每個架構各一份
FROM --platform=$BUILDPLATFORM node:22-slim AS build
# 專案 label:make clean 只清帶它的 image;兩個 stage 都要帶,build stage 留下的舊 image 才清得到
LABEL org.opencontainers.image.title="fullstack"
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
LABEL org.opencontainers.image.title="fullstack"
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
