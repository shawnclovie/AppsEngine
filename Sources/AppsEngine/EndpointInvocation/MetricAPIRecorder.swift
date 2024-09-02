import Foundation

public protocol APIMetricRecorder: Sendable {
	func record(to ctx: Context, response: HTTPResponse) async
}

public struct DefaultAPIMetricRecorder: APIMetricRecorder {
	private let metric: Metric

	init(metric: Metric) {
		self.metric = metric
	}

	public func record(to ctx: Context, response: HTTPResponse) async {
		let status = metricAPIStatus(code: response.status.code)
		let timecost = TimeDuration.since(ctx.startTime)
		let appName = ctx.config.metricName
		let endpointName = ctx.endpoint?.name ?? ""
		metricAPIAll(appName: appName, status: status, duration: timecost)
		metricAPIEndpoint(appName: appName, endpoint: endpointName, status: status, duration: timecost)
		if let err = await ctx.get(WrappedRequestError.self) {
			metric.count("\(appName).api.\(endpointName).failed.\(status).\(err.error.base.name)")
		}
	}

	private func metricAPIStatus(code: UInt) -> String {
		switch code {
		case 0 ..< 400:
			return "ok"
		case 400 ..< 500:
			return "4xx"
		default:
			return String(code)
		}
	}

	private func metricAPIAll(appName: String, status: String, duration: TimeDuration) {
		// count: {app_name}.api.all
		metric.count("\(appName).api.all")
		if status == "ok" {
			// time cost: {app_name}.api.all.timecost
			metric.timer("\(appName).api.all.ok.timecost", duration: duration.seconds)
		}
		// count: {app_name}.api.{suffix}.[ok|4xx|5xx]
		metric.count("\(appName).api.all.\(status)")
	}

	/// record API metric with `appName` for `endpoint` and `all`.
	private func metricAPIEndpoint(appName: String, endpoint: String, status: String, duration: TimeDuration) {
		let endpoint = endpoint.isEmpty ? "__not_found__" : endpoint
		for suffix in ["all", endpoint] {
			// count: {app_name}.api.endpoint.[all|{endpoint}]
			metric.count("\(appName).api.endpoint.\(suffix)")
			// count: {app_name}.api.endpoint.[all|{endpoint}].[ok|4xx|5xx]
			metric.count("\(appName).api.endpoint.\(suffix).\(status)")
			if status == "ok" {
				// time cost: {app_name}.api.endpoint.[all|{endpoint}].ok.timecost
				metric.timer("\(appName).api.endpoint.\(suffix).ok.timecost", duration: duration.seconds)
			}
		}
	}
}
