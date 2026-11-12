'use strict';
'require view';
'require fs';
'require ui';
'require network';

/*
 * LuCI entry point for honk.
 *
 * The real dashboard is doona, served by honk-core on port 9527. It is a
 * separate origin from LuCI, so it cannot be embedded in an iframe (honk sends
 * X-Frame-Options and a Host/Origin allow-list). This page therefore only
 * reports the service state and opens the panel in a new tab.
 */

function run(cmd, args) {
	return fs.exec(cmd, args || []).then(function (res) {
		return { code: res.code, out: (res.stdout || '').trim() };
	}).catch(function (err) {
		return { code: -1, out: String(err) };
	});
}

return view.extend({
	load: function () {
		return Promise.all([
			run('/usr/libexec/honk-status'),
			L.resolveDefault(network.getNetwork('lan'), null)
		]);
	},

	panelUrl: function (lan) {
		var host = window.location.hostname;
		if (!/^\d+\.\d+\.\d+\.\d+$/.test(host))
			host = lan ? lan.getIPAddr() : null;
		return host ? 'http://' + host + ':9527/ui/' : null;
	},

	render: function (data) {
		var status = data[0];
		var states = status.code === 0 ? status.out.split(/\s+/) : [];
		var enabled = states.indexOf('enabled') !== -1;
		var running = states.indexOf('running') !== -1;
		var url = this.panelUrl(data[1]);
		var readOnly = !L.hasViewPermission();

		var stateRow = function (label, value, good) {
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '33%' }, label),
				E('td', { 'class': 'td left' }, [
					E('span', { 'style': good ? 'color:#2e7d32;font-weight:bold' : 'color:#c62828;font-weight:bold' }, value)
				])
			]);
		};

		var action = function (verb, label) {
			return E('button', {
				'class': 'btn cbi-button',
				'disabled': readOnly || status.code !== 0 || null,
				'click': ui.createHandlerFn(this, function () {
					return run('/etc/init.d/honk', [verb]).then(function (result) {
						if (result.code !== 0) {
							ui.addNotification(null, E('p', {}, '服务操作失败，请查看系统日志。'));
							return;
						}
						window.location.reload();
					});
				})
			}, label);
		};

		return E([
			E('h2', {}, 'Honk 代理'),
			E('div', { 'class': 'cbi-map-descr' },
				'本版本的透明代理由 honk 提供，控制面板是内嵌的 doona。' +
				'doona 是一个独立的 Web 应用，不在 LuCI 内，需要在新标签页打开。'),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, '服务状态'),
				E('table', { 'class': 'table' }, [
					stateRow('开机自启', status.code !== 0 ? '无法查询' : enabled ? '已启用' : '已停用', enabled),
					stateRow('当前状态', status.code !== 0 ? '无法查询' : running ? '运行中' : '未运行', running),
					stateRow('面板地址', url || '请使用路由器的 LAN IPv4 地址访问', !!url)
				])
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, '操作'),
				E('div', { 'class': 'cbi-page-actions' }, [
					E('button', {
						'class': 'btn cbi-button cbi-button-apply',
						'disabled': !url || null,
						'click': function () { if (url) window.open(url, '_blank', 'noopener'); }
					}, '打开 doona 面板'),
					' ',
					enabled ? action('disable', '取消开机自启') : action('enable', '设置开机自启'),
					' ',
					running ? action('stop', '停止服务') : action('start', '启动服务')
				])
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, '说明'),
				E('ul', {}, [
					E('li', {}, '首次打开 doona 需要创建管理员账号，账号保存在 /etc/honk/data/state/honk.db。'),
					E('li', {}, '代理节点、订阅与分流规则都在 doona 中配置，配置文件是 /etc/honk/config.dae。'),
					E('li', {}, '默认路由为全部直连：配置节点之前不会产生任何代理流量。'),
					E('li', {}, 'Honk 为测试版。启用后请确认路由器管理页面和 LAN DNS 仍然可用。')
				])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
