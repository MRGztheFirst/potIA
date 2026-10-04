import 'package:flutter_test/flutter_test.dart';
import 'package:potia_app/core/utils/validators.dart';
import 'package:potia_app/models/chat_message.dart';
import 'package:potia_app/services/sse_parser.dart';

void main() {
  group('Validators', () {
    test('email', () {
      expect(Validators.email('ana@potia.com'), isNull);
      expect(Validators.email('ana-potia.com'), 'E-mail inválido');
      expect(Validators.email(''), 'Informe seu e-mail');
    });

    test('senha de cadastro', () {
      expect(Validators.newPassword('receita123'), isNull);
      expect(Validators.newPassword('curta1'), 'A senha deve ter pelo menos 8 caracteres');
      expect(Validators.newPassword('semnumeros'), 'Inclua pelo menos um número');
      expect(Validators.newPassword('12345678'), 'Inclua pelo menos uma letra');
    });

    test('confirmação de senha', () {
      final validator = Validators.confirmPassword(() => 'receita123');
      expect(validator('receita123'), isNull);
      expect(validator('outra123'), 'As senhas não coincidem');
    });
  });

  group('SseParser', () {
    test('agrupa linhas data em eventos', () async {
      final lines = Stream.fromIterable([
        ': keep-alive',
        'data: {"type":"token","content":"Olá"}',
        '',
        'event: fim',
        'data: linha 1',
        'data: linha 2',
        '',
      ]);
      final events = await lines.transform(const SseParser()).toList();
      expect(events, hasLength(2));
      expect(events[0].data, '{"type":"token","content":"Olá"}');
      expect(events[1].event, 'fim');
      expect(events[1].data, 'linha 1\nlinha 2');
    });
  });

  group('ChatMessage', () {
    test('converte para o formato da API', () {
      final message = ChatMessage.user('Como fazer pão?');
      expect(message.toApiJson(), {'role': 'user', 'content': 'Como fazer pão?'});
      expect(ChatMessage.assistantPlaceholder().isStreaming, isTrue);
    });
  });
}
