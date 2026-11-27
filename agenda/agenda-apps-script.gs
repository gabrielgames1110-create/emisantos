/**
 * Agenda do site Emi Santos (Google Planilhas + Apps Script)
 *
 * 1. Na planilha: Extensões > Apps Script. Apague o conteúdo e cole este arquivo inteiro.
 * 2. Salve, escolha a função "configurar" no topo e clique em Executar (só uma vez).
 * 3. Implantar > Nova implantação > App da Web
 *    Executar como: Eu  |  Quem pode acessar: Qualquer pessoa
 * 4. Copie a URL que termina em /exec e cole no site, no ajuste "Link da planilha".
 */

var ABA = {
  servicos: 'Serviços',
  horarios: 'Horários',
  bloqueios: 'Bloqueios',
  agendamentos: 'Agendamentos',
  config: 'Config'
};

function configurar() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  ss.setSpreadsheetLocale('pt_BR');
  ss.setSpreadsheetTimeZone('America/Sao_Paulo');

  var serv = aba_(ss, ABA.servicos, ['Serviço', 'Duração (min)', 'Valor (R$)']);
  serv.getRange('C2:C').setNumberFormat('"R$" #,##0.00');
  if (serv.getLastRow() < 2) {
    serv.getRange(2, 1, 8, 3).setValues([
      ['Aplicação volume brasileiro', 100, 150],
      ['Aplicação volume 5D', 100, 150],
      ['Aplicação fox eyes', 100, 150],
      ['Lash lifting', 80, 75],
      ['Manutenção volume brasileiro', 80, 80],
      ['Manutenção volume egípcio', 80, 80],
      ['Manutenção fox eyes', 80, 80],
      ['Ensaio fotográfico', 120, 200]
    ]);
  }

  var hor = aba_(ss, ABA.horarios, ['Dia', 'Abre', 'Fecha', 'Pausa início', 'Pausa fim']);
  hor.getRange('B2:E').setNumberFormat('hh:mm');
  if (hor.getLastRow() < 2) {
    hor.getRange(2, 1, 7, 5).setValues([
      ['Segunda', '09:00', '18:00', '12:00', '13:00'],
      ['Terça', '09:00', '18:00', '12:00', '13:00'],
      ['Quarta', '09:00', '18:00', '12:00', '13:00'],
      ['Quinta', '09:00', '18:00', '12:00', '13:00'],
      ['Sexta', '09:00', '18:00', '12:00', '13:00'],
      ['Sábado', '09:00', '13:00', '', ''],
      ['Domingo', '', '', '', '']
    ]);
  }

  var blq = aba_(ss, ABA.bloqueios, ['Data', 'Início', 'Fim', 'Motivo']);
  blq.getRange('A2:A').setNumberFormat('dd/mm/yyyy');
  blq.getRange('B2:C').setNumberFormat('hh:mm');

  var ag = aba_(ss, ABA.agendamentos, ['Data', 'Hora', 'Serviço', 'Duração (min)', 'Nome', 'WhatsApp', 'Status', 'Pedido em']);
  ag.getRange('A2:A').setNumberFormat('dd/mm/yyyy');
  ag.getRange('B2:B').setNumberFormat('@');
  ag.getRange('F2:F').setNumberFormat('@');
  ag.getRange('H2:H').setNumberFormat('dd/mm/yyyy hh:mm');
  ag.getRange('G2:G').setDataValidation(
    SpreadsheetApp.newDataValidation().requireValueInList(['Pendente', 'Confirmado', 'Cancelado'], true).build()
  );
  ag.setConditionalFormatRules([
    cor_(ag, 'Pendente', '#F6EBD9'),
    cor_(ag, 'Confirmado', '#DDEBDF'),
    cor_(ag, 'Cancelado', '#EEEEEE')
  ]);

  var cfg = aba_(ss, ABA.config, ['Configuração', 'Valor']);
  if (cfg.getLastRow() < 2) {
    cfg.getRange(2, 1, 4, 2).setValues([
      ['Intervalo entre horários (min)', 30],
      ['Dias disponíveis à frente', 30],
      ['Antecedência mínima (horas)', 12],
      ['E-mail para avisos (opcional)', '']
    ]);
  }

  var padrao = ss.getSheetByName('Página1') || ss.getSheetByName('Sheet1');
  if (padrao && padrao.getLastRow() === 0 && ss.getSheets().length > 1) ss.deleteSheet(padrao);
}

function doGet() {
  var dados = dados_(SpreadsheetApp.getActiveSpreadsheet());
  delete dados.config.email;
  return json_(dados);
}

function doPost(e) {
  var lock = LockService.getScriptLock();
  lock.waitLock(15000);
  try {
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var p = JSON.parse((e && e.postData && e.postData.contents) || '{}');
    var d = dados_(ss);
    var servico = d.servicos.filter(function (s) { return s.nome === p.servico; })[0];
    var nome = String(p.nome || '').trim().slice(0, 80);
    var whats = String(p.whatsapp || '').replace(/\D/g, '').slice(0, 15);
    if (!servico || !nome || whats.length < 10 || !/^\d{2}\/\d{2}\/\d{4}$/.test(p.data) || !/^\d{1,2}:\d{2}$/.test(p.hora)) {
      return json_({ ok: false, erro: 'dados' });
    }
    var ini = min_(p.hora), fim = ini + servico.duracao;
    var choca = function (a, b) { return ini < b && fim > a; };
    var ocupado = d.ocupados.some(function (o) { return data_(o.data) === p.data && choca(min_(o.hora), min_(o.hora) + o.duracao); }) ||
      d.bloqueios.some(function (b) { return data_(b.data) === p.data && choca(b.inicio ? min_(b.inicio) : 0, b.fim ? min_(b.fim) : 1440); });
    if (ocupado) return json_({ ok: false, erro: 'ocupado' });

    var partes = p.data.split('/');
    ss.getSheetByName(ABA.agendamentos).appendRow([
      new Date(Number(partes[2]), Number(partes[1]) - 1, Number(partes[0]), 12),
      p.hora, servico.nome, servico.duracao, nome, whats, 'Pendente', new Date()
    ]);

    if (d.config.email) {
      MailApp.sendEmail(d.config.email, 'Novo pedido: ' + servico.nome + ' em ' + p.data + ' às ' + p.hora,
        'Nome: ' + nome + '\nWhatsApp: ' + whats + '\nServiço: ' + servico.nome + '\nData: ' + p.data + ' às ' + p.hora +
        '\n\nConfirme ou cancele na aba Agendamentos da planilha.');
    }
    return json_({ ok: true });
  } catch (err) {
    return json_({ ok: false, erro: 'servidor' });
  } finally {
    lock.releaseLock();
  }
}

function dados_(ss) {
  return {
    servicos: linhas_(ss, ABA.servicos).filter(function (r) { return r[0]; }).map(function (r) {
      return { nome: r[0], duracao: parseInt(r[1], 10) || 60, valor: r[2] || '' };
    }),
    horarios: linhas_(ss, ABA.horarios).filter(function (r) { return r[0]; }).map(function (r) {
      return { dia: r[0], abre: r[1], fecha: r[2], pausaInicio: r[3], pausaFim: r[4] };
    }),
    bloqueios: linhas_(ss, ABA.bloqueios).filter(function (r) { return r[0]; }).map(function (r) {
      return { data: r[0], inicio: r[1], fim: r[2] };
    }),
    ocupados: linhas_(ss, ABA.agendamentos).filter(function (r) {
      return r[0] && r[1] && String(r[6]).toLowerCase() !== 'cancelado';
    }).map(function (r) {
      return { data: r[0], hora: r[1], duracao: parseInt(r[3], 10) || 60 };
    }),
    config: config_(ss)
  };
}

function config_(ss) {
  var c = { intervalo: 30, diasFrente: 30, antecedencia: 12, email: '' };
  linhas_(ss, ABA.config).forEach(function (r) {
    var k = String(r[0]).toLowerCase(), v = r[1];
    if (k.indexOf('intervalo') === 0) c.intervalo = parseInt(v, 10) || c.intervalo;
    else if (k.indexOf('dias') === 0) c.diasFrente = parseInt(v, 10) || c.diasFrente;
    else if (k.indexOf('anteced') === 0) c.antecedencia = v === '' ? c.antecedencia : (parseFloat(String(v).replace(',', '.')) || 0);
    else if (k.indexOf('e-mail') === 0) c.email = String(v).trim();
  });
  return c;
}

function linhas_(ss, nome) {
  var sh = ss.getSheetByName(nome);
  if (!sh || sh.getLastRow() < 2) return [];
  return sh.getRange(2, 1, sh.getLastRow() - 1, sh.getLastColumn()).getDisplayValues().map(function (r) {
    return r.map(function (c) { return String(c).trim(); });
  });
}

function aba_(ss, nome, cab) {
  var sh = ss.getSheetByName(nome) || ss.insertSheet(nome);
  sh.getRange(1, 1, 1, cab.length).setValues([cab]).setFontWeight('bold');
  sh.setFrozenRows(1);
  return sh;
}

function cor_(sh, texto, fundo) {
  return SpreadsheetApp.newConditionalFormatRule().whenTextEqualTo(texto).setBackground(fundo).setRanges([sh.getRange('G2:G')]).build();
}

function data_(s) {
  var m = String(s).match(/(\d{1,2})\/(\d{1,2})\/(\d{4})/);
  return m ? ('0' + m[1]).slice(-2) + '/' + ('0' + m[2]).slice(-2) + '/' + m[3] : '';
}

function min_(h) {
  var m = String(h).match(/(\d{1,2}):(\d{2})/);
  return m ? Number(m[1]) * 60 + Number(m[2]) : 0;
}

function json_(o) {
  return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON);
}
