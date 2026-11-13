local Translations = {
    success = {
        withdraw = 'Levantamento efetuado com sucesso',
        deposit = 'Depósito efetuado com sucesso',
        transfer = 'Transferência efetuada com sucesso',
        account = 'Conta criada',
        rename = 'Conta renomeada',
        delete = 'Conta eliminada',
        userAdd = 'Utilizador adicionado',
        userRemove = 'Utilizador removido',
        card = 'Cartão criado',
        give = '$%s em dinheiro entregues',
        receive = '$%s em dinheiro recebidos',
    },
    error = {
        error = 'Ocorreu um erro',
        access = 'Não autorizado',
        account = 'Conta não encontrada',
        accounts = 'Limite máximo de contas atingido',
        user = 'Utilizador já adicionado',
        noUser = 'Utilizador não encontrado',
        money = 'Dinheiro insuficiente',
        pin = 'PIN inválido',
        card = 'Nenhum cartão bancário encontrado',
        amount = 'Montante inválido',
        toofar = 'Estás demasiado longe',
    },
    progress = {
        atm = 'A aceder ao multibanco',
    }
}

Lang = Lang or Locale:new({ warnOnMissing = true })
Lang:addLocale('pt', Translations)

return Translations
