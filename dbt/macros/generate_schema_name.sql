{#
  prod：モデルごとの +schema（staging / intermediate / marts）をそのままデータセット名にする
  dev・ci：target.schema（dbt_{user} / ci_pr_{番号}）の 1 データセットにまとめる（D-13、D-20）
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if target.name == 'prod' and custom_schema_name is not none -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ target.schema }}
    {%- endif -%}
{%- endmacro %}
