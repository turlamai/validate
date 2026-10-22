# validate

[English](README.md) · **中文**

[![CI](https://github.com/turinglambdaai/validate/actions/workflows/ci.yml/badge.svg)](https://github.com/turinglambdaai/validate/actions/workflows/ci.yml)

Racket 的 schema 校验与 typed JSON 解码库。声明一次 schema，到处解析不可信数据——拿到验证过的值或带路径的错误，zod 工作流，落在 JSON 边界上。

## 安装

```
raco pkg install validate
```

## 使用

```racket
(require validate)

(define post-schema
  (object #:fields
          (list (field 'title (string-schema #:min-length 1))
                (field 'kind (enum '("news" "paper" "github")))
                (field 'score (int-schema #:min 0 #:max 10) #:optional #t #:default 0)
                (field 'tags (list-of (string-schema)) #:optional #t #:default '()))))

(parse post-schema (some-untrusted-payload))
;; => '#hash((title . "...") (kind . "news") (score . 0) (tags . ()))

(parse-safe post-schema (hasheq 'title 99))
;; => (err (list (validate-error '(title) "a string" 99 ...)))

;; JSON 边界，双向
(define payload (read-json (open-input-string body)))   ; 不可信
(define post (parse (jsexpr-schema post-schema) payload))
(jsexpr-encode (hasheq 'ok #t 'kind 'done))             ; symbol 也没问题
```

- object 查键同时接受字符串与符号键、equal 与 eq hash——JSON 解码产物和手搓 `hasheq` 都能解
- 错误带从根到叶的路径：`items.[1].title: expected a string (got: 99)`
- `parse-safe` 一遍收集所有问题；`parse` 一次性抛出
- `to-jsexpr`/`jsexpr-encode` 归一化 symbol、keyword、vector、可变 hash，不再撞 json 模块的契约炸弹

## 开发

```
raco pkg install --auto --link .
raco test tests
raco setup --check-pkg-deps -l validate
```

## 许可

[MIT](LICENSE)
