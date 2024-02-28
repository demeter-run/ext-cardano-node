use bytes::Bytes;
use http_body_util::{combinators::BoxBody, BodyExt, Full};
use hyper::Response;

pub type Body = BoxBody<Bytes, hyper::Error>;
pub type ProxyResponse = Response<Body>;

pub fn full<T: Into<Bytes>>(chunk: T) -> Body {
    Full::new(chunk.into())
        .map_err(|never| match never {})
        .boxed()
}
