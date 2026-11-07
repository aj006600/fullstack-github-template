FROM node:22-slim AS build
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
