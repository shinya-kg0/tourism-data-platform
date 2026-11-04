"""GCS の操作：元ファイルの取得と、archive / rejected への移動（仕様書 4.1、5.1）"""

from pathlib import Path, PurePosixPath

from google.cloud import storage


def suffixed_name(object_name: str, generation: int) -> str:
    """移動先の名前。上げ直しで上書きしないよう、拡張子の前に世代番号を付ける"""
    p = PurePosixPath(object_name)
    return str(p.with_name(f"{p.stem}__{generation}{p.suffix}"))


class Store:
    def __init__(self, project: str, buckets: dict[str, str], client: storage.Client | None = None):
        self.client = client or storage.Client(project=project)
        self.buckets = buckets  # 用途（landing / archive / rejected）→ バケット名

    def uri(self, object_name: str) -> str:
        return f"gs://{self.buckets['landing']}/{object_name}"

    def download(self, object_name: str, generation: int, dest: Path) -> str:
        """landing から指定の世代を取得し、MD5 ハッシュ（base64）を返す"""
        blob = self.client.bucket(self.buckets["landing"]).blob(object_name, generation=generation)
        blob.download_to_filename(dest)
        return blob.md5_hash

    def move(self, object_name: str, generation: int, to: str) -> str:
        """landing から archive / rejected へ移す。移動先の URI を返す"""
        src_bucket = self.client.bucket(self.buckets["landing"])
        blob = src_bucket.blob(object_name, generation=generation)
        new_name = suffixed_name(object_name, generation)
        src_bucket.copy_blob(blob, self.client.bucket(self.buckets[to]), new_name, source_generation=generation)
        blob.delete(if_generation_match=generation)
        return f"gs://{self.buckets[to]}/{new_name}"
