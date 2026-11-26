const express = require('express');
const mongoose = require('mongoose');
const bodyParser = require('body-parser');

// Inicializando o app Express
const app = express();
const port = Number(process.env.PORT || 5000);

// Configuracao do banco vem de variaveis de ambiente (nada fixo no codigo).
// Na nuvem quem preenche e o Ansible; localmente, o docker-compose.
const mongoHost = process.env.MONGO_HOST || 'mongo-todo';
const mongoPort = process.env.MONGO_PORT || '27017';
const mongoDb = process.env.MONGO_DB || 'todo-app';

const opcoesMongo = { serverSelectionTimeoutMS: 5000 };
if (process.env.MONGO_USER) {
  opcoesMongo.user = process.env.MONGO_USER;
  opcoesMongo.pass = process.env.MONGO_PASSWORD;
  opcoesMongo.authSource = process.env.MONGO_AUTH_SOURCE || mongoDb;
}

// Conecta no MongoDB e, se o banco ainda nao estiver pronto, tenta de novo
async function conectar() {
  try {
    await mongoose.connect(`mongodb://${mongoHost}:${mongoPort}/${mongoDb}`, opcoesMongo);
    console.log('Conectado ao MongoDB');
  } catch (err) {
    console.error('Erro ao conectar ao MongoDB, tentando de novo em 5s:', err.message);
    setTimeout(conectar, 5000);
  }
}
conectar();

// O frontend e a API ficam no mesmo endereco (o Nginx encaminha /todos),
// entao o CORS aberto do projeto original nao e mais necessario.
app.use(bodyParser.json());

// Definindo o modelo de Tarefa (To-do)
const TodoSchema = new mongoose.Schema({
  text: { type: String, required: true },
  completed: { type: Boolean, default: false },
});

const Todo = mongoose.model('Todo', TodoSchema);

// Verificacao de saude: so responde 200 se a API estiver conectada ao banco.
// O load balancer e a pipeline usam essa rota.
app.get('/health', (req, res) => {
  const conectado = mongoose.connection.readyState === 1;
  res.status(conectado ? 200 : 503).json({
    status: conectado ? 'ok' : 'erro',
    banco: conectado ? 'conectado' : 'desconectado',
    versao: process.env.APP_VERSION || 'local',
  });
});

// Rota para obter todas as tarefas (GET)
app.get('/todos', async (req, res) => {
  try {
    const todos = await Todo.find(); // Retorna todas as tarefas do banco
    res.json(todos);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Rota para adicionar uma nova tarefa (POST)
app.post('/todos', async (req, res) => {
  const { text } = req.body; // Obtém o texto da tarefa do corpo da requisição

  // Verifica se o campo "text" está presente
  if (!text) {
    return res.status(400).json({ message: 'O campo "text" é obrigatório' });
  }

  const todo = new Todo({
    text,
    completed: false,
  });

  try {
    const newTodo = await todo.save(); // Salva a tarefa no banco
    res.status(201).json(newTodo); // Retorna a tarefa criada
  } catch (err) {
    res.status(400).json({ message: err.message }); // Retorna erro se houver falha no banco de dados
  }
});

// Rota para marcar uma tarefa como concluída (PATCH)
app.patch('/todos/:id', async (req, res) => {
  try {
    const todo = await Todo.findById(req.params.id); // Encontra a tarefa pelo ID

    if (!todo) {
      return res.status(404).json({ message: 'Tarefa não encontrada' });
    }

    // Alterna o status de "completed" da tarefa
    todo.completed = !todo.completed;
    await todo.save(); // Salva a tarefa modificada
    res.json(todo); // Retorna a tarefa atualizada
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Rota para excluir uma tarefa (DELETE)
app.delete('/todos/:id', async (req, res) => {
  try {
    const todo = await Todo.findByIdAndDelete(req.params.id); // Deleta a tarefa pelo ID

    if (!todo) {
      return res.status(404).json({ message: 'Tarefa não encontrada' });
    }

    res.json({ message: 'Tarefa excluída com sucesso' }); // Retorna uma mensagem de sucesso
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Iniciando o servidor
app.listen(port, () => {
  console.log(`Servidor rodando na porta ${port}`);
});
